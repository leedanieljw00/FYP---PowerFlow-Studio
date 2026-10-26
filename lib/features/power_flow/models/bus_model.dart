import '../../../core/math/power_flow_common.dart';
import '../../../core/utils/format.dart';

/// App data model representing an electrical bus in the power system.
class BusModel {
  const BusModel({
    required this.id,
    required this.busNumber,
    required this.name,
    required this.type,
    this.vMag = 1.0,
    this.angleDeg = 0.0,
    this.pGen = 0.0,
    this.qGen = 0.0,
    this.pLoad = 0.0,
    this.qLoad = 0.0,
    this.qMin,
    this.qMax,
  });

  final String id;
  final int busNumber; // 1-based bus number
  final String name;
  final BusType type;
  final double vMag;
  final double angleDeg;
  final double pGen;
  final double qGen;
  final double pLoad;
  final double qLoad;
  final double? qMin;
  final double? qMax;

  /// Net scheduled real power injection: P_G - P_L
  double get pNet => pGen - pLoad;

  /// Net scheduled reactive power injection: Q_G - Q_L
  double get qNet => qGen - qLoad;

  /// Convert to solver-level [PfBus] with angle converted to radians
  PfBus toPfBus() {
    return PfBus(
      type: type,
      vMag: vMag,
      angle: angleDeg * kRadPerDeg,
      pGen: pGen,
      qGen: qGen,
      pLoad: pLoad,
      qLoad: qLoad,
      qMin: qMin,
      qMax: qMax,
    );
  }

  BusModel copyWith({
    String? id,
    int? busNumber,
    String? name,
    BusType? type,
    double? vMag,
    double? angleDeg,
    double? pGen,
    double? qGen,
    double? pLoad,
    double? qLoad,
    double? Function()? qMin,
    double? Function()? qMax,
  }) {
    return BusModel(
      id: id ?? this.id,
      busNumber: busNumber ?? this.busNumber,
      name: name ?? this.name,
      type: type ?? this.type,
      vMag: vMag ?? this.vMag,
      angleDeg: angleDeg ?? this.angleDeg,
      pGen: pGen ?? this.pGen,
      qGen: qGen ?? this.qGen,
      pLoad: pLoad ?? this.pLoad,
      qLoad: qLoad ?? this.qLoad,
      qMin: qMin != null ? qMin() : this.qMin,
      qMax: qMax != null ? qMax() : this.qMax,
    );
  }
}
