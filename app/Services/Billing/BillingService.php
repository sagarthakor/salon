<?php

namespace App\Services\Billing;

use App\Enums\InvoiceStatus;
use App\Enums\PaymentStatus;
use App\Events\InvoicePaid;
use App\Events\PaymentFailed;
use App\Events\PaymentSucceeded;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\Plan;
use App\Models\Subscription;
use App\Models\Tenant;
use App\Services\Billing\Gateways\PaymentGatewayInterface;
use App\Support\InvoiceNumberGenerator;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Owns invoice/payment creation, totals, and marking paid/failed. Never
 * duplicated in a controller — see SAAS_BILLING_ARCHITECTURE.md.
 */
class BillingService
{
    public function __construct(
        private readonly PaymentGatewayInterface $gateway,
        private readonly SubscriptionService $subscriptions,
        private readonly InvoiceNumberGenerator $invoiceNumbers,
    ) {}

    /**
     * Starts (or resumes, if [$idempotencyKey] matches a pending attempt
     * already in flight) a checkout for [$plan] against [$tenant]'s
     * subscription. The amount charged is *always* `$plan->amount` — the
     * caller passes only a plan id; nothing price-related ever comes from
     * the client (see SAAS_BILLING_ARCHITECTURE.md, "Amount tampering").
     */
    public function initiateCheckout(Tenant $tenant, Subscription $subscription, Plan $plan, ?string $idempotencyKey): Payment
    {
        $payment = null;
        if ($idempotencyKey !== null) {
            $existing = Payment::query()
                ->where('idempotency_key', $idempotencyKey)
                ->whereIn('status', [PaymentStatus::PENDING, PaymentStatus::PAID])
                ->first();
            if ($existing !== null && ($existing->status === PaymentStatus::PAID || $existing->gateway_order_id !== null)) {
                return $existing;
            }
            // A PENDING payment with no gateway_order_id yet is a prior
            // attempt whose gateway call never completed (see below) —
            // reuse it rather than creating a second invoice for the same
            // idempotency key.
            $payment = $existing;
        }

        $payment ??= DB::transaction(function () use ($tenant, $subscription, $plan, $idempotencyKey): Payment {
            $invoice = $this->openInvoiceFor($tenant, $subscription, $plan);

            return Payment::query()->create([
                'tenant_id' => $tenant->id,
                'subscription_id' => $subscription->id,
                'invoice_id' => $invoice->id,
                'amount' => $plan->amount,
                'currency' => $plan->currency,
                'status' => PaymentStatus::PENDING,
                'gateway' => $this->gateway->name(),
                'idempotency_key' => $idempotencyKey ?? (string) Str::ulid(),
            ]);
        });

        // Deliberately outside any DB transaction/lock: this is a real
        // outbound HTTPS call to the gateway, and a slow or unresponsive
        // gateway must never hold a database connection or row lock open
        // for the duration of the round trip. If this call throws, the
        // Payment row above is already committed as PENDING with no
        // gateway_order_id — a retry with the same idempotency key reuses
        // that row (see above) instead of accumulating a new invoice per
        // failed attempt. See "Checkout no longer holds a DB transaction
        // across the gateway call" in PERFORMANCE_HARDENING.md.
        $order = $this->gateway->createOrder(receipt: $payment->id, amount: (float) $plan->amount, currency: $plan->currency, notes: [
            'tenant_id' => $tenant->id,
            'plan_code' => $plan->code,
        ]);
        $payment->update(['gateway_order_id' => $order->id]);

        return $payment->refresh();
    }

    /**
     * Creates a fresh OPEN invoice with one line item that snapshots the
     * plan's *current* name/price — see SAAS_BILLING_ARCHITECTURE.md,
     * "Plan price history": a later plan price change can never alter this
     * invoice once it exists.
     */
    public function openInvoiceFor(Tenant $tenant, Subscription $subscription, Plan $plan): Invoice
    {
        return DB::transaction(function () use ($tenant, $subscription, $plan): Invoice {
            $now = CarbonImmutable::now();
            // `current_period_end` is cast `datetime` (a mutable Carbon), like
            // every other model-sourced date in this codebase — converted to
            // CarbonImmutable here rather than mutating the model's own
            // attribute in place via addInterval()'s addMonths()/etc.
            $periodStart = $subscription->current_period_end !== null
                ? CarbonImmutable::instance($subscription->current_period_end)
                : $now;
            $periodEnd = $this->subscriptions->addInterval($periodStart, $plan);

            $invoice = Invoice::query()->create([
                'tenant_id' => $tenant->id,
                'subscription_id' => $subscription->id,
                'invoice_number' => $this->invoiceNumbers->next(),
                'subtotal' => $plan->amount,
                'tax' => 0,
                'total' => $plan->amount,
                'currency' => $plan->currency,
                'status' => InvoiceStatus::OPEN,
                'billing_period_start' => $periodStart,
                'billing_period_end' => $periodEnd,
                'issued_at' => $now,
                'due_at' => $now,
            ]);
            $invoice->items()->create([
                'tenant_id' => $tenant->id,
                'description' => $plan->name.' ('.$plan->billing_interval_count.' '.$plan->billing_interval->value.')',
                'quantity' => 1,
                'unit_amount' => $plan->amount,
                'amount' => $plan->amount,
                'metadata' => ['plan_code' => $plan->code],
            ]);

            return $invoice;
        });
    }

    /**
     * The single path both the client-driven verify endpoint and the
     * webhook handler call — idempotent by construction: a payment already
     * PAID is returned unchanged rather than reprocessed, so whichever of
     * the two arrives first "wins" and the second is a safe no-op.
     */
    public function verifyAndFinalize(Payment $payment, string $gatewayPaymentId, string $gatewaySignature): Payment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }
        if ($payment->gateway_order_id === null) {
            return $this->recordPaymentFailure($payment, 'Payment has no associated gateway order.');
        }
        $verified = $this->gateway->verifyPaymentSignature($payment->gateway_order_id, $gatewayPaymentId, $gatewaySignature);
        if (! $verified) {
            return $this->recordPaymentFailure($payment, 'Gateway signature verification failed.');
        }

        return $this->recordPaymentSuccess($payment, $gatewayPaymentId, $gatewaySignature);
    }

    public function recordPaymentSuccess(Payment $payment, string $gatewayPaymentId, ?string $gatewaySignature = null): Payment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }

        return DB::transaction(function () use ($payment, $gatewayPaymentId, $gatewaySignature): Payment {
            $now = CarbonImmutable::now();
            $payment->update([
                'status' => PaymentStatus::PAID,
                'gateway_payment_id' => $gatewayPaymentId,
                'gateway_signature' => $gatewaySignature,
                'paid_at' => $now,
            ]);
            PaymentSucceeded::dispatch($payment);

            $invoice = $payment->invoice;
            if ($invoice !== null && $invoice->status !== InvoiceStatus::PAID) {
                $invoice->update(['status' => InvoiceStatus::PAID, 'paid_at' => $now]);
                InvoicePaid::dispatch($invoice);
            }

            $subscription = $payment->subscription;
            $plan = $subscription->plan;
            $this->subscriptions->activate($subscription, $plan, $now);

            return $payment->refresh();
        });
    }

    public function recordPaymentFailure(Payment $payment, string $reason): Payment
    {
        if ($payment->status === PaymentStatus::PAID) {
            return $payment;
        }
        $payment->update(['status' => PaymentStatus::FAILED, 'failed_at' => CarbonImmutable::now(), 'failure_reason' => $reason]);
        PaymentFailed::dispatch($payment);

        $subscription = $payment->subscription;
        if (in_array($subscription->status->value, ['trialing', 'active'], true)) {
            $this->subscriptions->markPastDue($subscription);
        }

        return $payment->refresh();
    }
}
