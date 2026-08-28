/// Mirrors the query parameters every `/reports/*` endpoint accepts (see
/// `HasReportFilterRules` on the backend) — a single value object so every
/// report screen shares one filter bar and one way of building query
/// parameters. Not every field applies to every report; a repository method
/// only sends the ones that make sense for its endpoint.
class ReportFilter {
  const ReportFilter({
    this.range = 'this_month',
    this.from,
    this.to,
    this.branchId,
    this.staffId,
    this.serviceId,
    this.categoryId,
    this.status,
    this.customerId,
    this.couponId,
    this.membershipPlanId,
    this.groupBy,
    this.page = 1,
    this.perPage = 20,
    this.sort,
    this.direction,
  });

  final String range;
  final String? from;
  final String? to;
  final String? branchId;
  final String? staffId;
  final String? serviceId;
  final String? categoryId;
  final String? status;
  final String? customerId;
  final String? couponId;
  final String? membershipPlanId;
  final String? groupBy;
  final int page;
  final int perPage;
  final String? sort;
  final String? direction;

  static const List<String> presets = ['today', 'yesterday', 'this_week', 'last_week', 'this_month', 'last_month', 'this_year', 'custom'];

  ReportFilter copyWith({
    String? range,
    String? from,
    String? to,
    String? branchId,
    bool clearBranchId = false,
    String? staffId,
    bool clearStaffId = false,
    String? serviceId,
    bool clearServiceId = false,
    String? categoryId,
    bool clearCategoryId = false,
    String? status,
    bool clearStatus = false,
    String? customerId,
    String? couponId,
    String? membershipPlanId,
    String? groupBy,
    int? page,
    int? perPage,
    String? sort,
    String? direction,
  }) {
    return ReportFilter(
      range: range ?? this.range,
      from: from ?? this.from,
      to: to ?? this.to,
      branchId: clearBranchId ? null : (branchId ?? this.branchId),
      staffId: clearStaffId ? null : (staffId ?? this.staffId),
      serviceId: clearServiceId ? null : (serviceId ?? this.serviceId),
      categoryId: clearCategoryId ? null : (categoryId ?? this.categoryId),
      status: clearStatus ? null : (status ?? this.status),
      customerId: customerId ?? this.customerId,
      couponId: couponId ?? this.couponId,
      membershipPlanId: membershipPlanId ?? this.membershipPlanId,
      groupBy: groupBy ?? this.groupBy,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      sort: sort ?? this.sort,
      direction: direction ?? this.direction,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'range': range,
      'from': ?from,
      'to': ?to,
      'branch_id': ?branchId,
      'staff_id': ?staffId,
      'service_id': ?serviceId,
      'category_id': ?categoryId,
      'status': ?status,
      'customer_id': ?customerId,
      'coupon_id': ?couponId,
      'membership_plan_id': ?membershipPlanId,
      'group_by': ?groupBy,
      'page': page,
      'per_page': perPage,
      'sort': ?sort,
      'direction': ?direction,
    };
  }

  static String presetLabel(String preset) => switch (preset) {
    'today' => 'Today',
    'yesterday' => 'Yesterday',
    'this_week' => 'This week',
    'last_week' => 'Last week',
    'this_month' => 'This month',
    'last_month' => 'Last month',
    'this_year' => 'This year',
    'custom' => 'Custom range',
    _ => preset,
  };
}
