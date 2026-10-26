import '../../../core/math/ybus_builder.dart';

/// App data model representing a transmission line or transformer branch.
class LineModel {
  const LineModel({
    required this.id,
    required this.fromBus,
    required this.toBus,
    required this.r,
    required this.x,
    this.bHalf = 0.0,
    this.tap = 1.0,
  });

  final String id;
  final int fromBus; // 1-based bus number
  final int toBus;   // 1-based bus number
  final double r;
  final double x;
  final double bHalf;
  final double tap;

  /// Converts to solver-level [BranchParams] using a mapping from
  /// 1-based bus numbers to 0-based array indices.
  BranchParams toBranchParams(Map<int, int> busNumberToIndex) {
    final fromIdx = busNumberToIndex[fromBus];
    final toIdx = busNumberToIndex[toBus];

    if (fromIdx == null || toIdx == null) {
      throw ArgumentError(
        'Line connecting Bus $fromBus to Bus $toBus references unknown bus.',
      );
    }

    return BranchParams(
      from: fromIdx,
      to: toIdx,
      r: r,
      x: x,
      bHalf: bHalf,
      tap: tap,
    );
  }

  LineModel copyWith({
    String? id,
    int? fromBus,
    int? toBus,
    double? r,
    double? x,
    double? bHalf,
    double? tap,
  }) {
    return LineModel(
      id: id ?? this.id,
      fromBus: fromBus ?? this.fromBus,
      toBus: toBus ?? this.toBus,
      r: r ?? this.r,
      x: x ?? this.x,
      bHalf: bHalf ?? this.bHalf,
      tap: tap ?? this.tap,
    );
  }
}
