/// Shared parsing helper — every report's `data`/breakdown lists are plain
/// arrays of flat objects, so table rows are read directly rather than
/// wrapped in a dedicated class per report (the field names are already
/// self-descriptive, e.g. `branch_name`, `net_revenue`).
List<Map<String, dynamic>> reportRows(dynamic value) =>
    (value as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
