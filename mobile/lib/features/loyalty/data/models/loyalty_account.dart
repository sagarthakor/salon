/// Mirrors `App\Http\Resources\LoyaltyAccountResource`.
class LoyaltyAccount {
  const LoyaltyAccount({
    required this.id,
    required this.balance,
    required this.lifetimeEarned,
    required this.lifetimeRedeemed,
  });

  factory LoyaltyAccount.fromJson(Map<String, dynamic> json) => LoyaltyAccount(
    id: json['id'] as String,
    balance: json['balance'] as int,
    lifetimeEarned: json['lifetime_earned'] as int,
    lifetimeRedeemed: json['lifetime_redeemed'] as int,
  );

  final String id;
  final int balance;
  final int lifetimeEarned;
  final int lifetimeRedeemed;
}
