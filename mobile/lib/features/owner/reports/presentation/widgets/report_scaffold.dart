import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../shared/widgets/state_views.dart';
import 'report_filter_bar.dart';

/// The loading/error/pull-to-refresh shell every report screen shares —
/// only the filter bar and the loaded body differ between reports. Handles
/// instructions #54/#55/#71 (loading, error mapped via ApiException.message,
/// pull-to-refresh) in one place.
class ReportScaffold<T> extends ConsumerWidget {
  const ReportScaffold({
    super.key,
    required this.title,
    required this.provider,
    required this.builder,
    this.showBranchFilter = false,
  });

  final String title;
  final ProviderBase<AsyncValue<T>> provider;
  final Widget Function(BuildContext context, T data) builder;
  final bool showBranchFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          ReportFilterBar(showBranchFilter: showBranchFilter),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(provider),
              child: async.when(
                loading: () => const LoadingView(),
                error: (error, stackTrace) => ListView(
                  children: [
                    SizedBox(
                      height: 400,
                      child: ErrorView(message: error.toString(), onRetry: () => ref.invalidate(provider)),
                    ),
                  ],
                ),
                data: (data) => builder(context, data),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
