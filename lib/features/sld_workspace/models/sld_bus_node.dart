import 'package:flutter/material.dart';

import '../../../core/math/power_flow_common.dart';

/// Visual and electrical representation of a busbar node on the SLD canvas.
class SldBusNode {
  const SldBusNode({
    required this.busNumber,
    required this.name,
    required this.type,
    required this.position,
    this.isVertical = false,
    this.length = 80.0,
    this.vMag = 1.0,
    this.angleDeg = 0.0,
    this.pGen = 0.0,
    this.qGen = 0.0,
    this.pLoad = 0.0,
    this.qLoad = 0.0,
    this.qMin,
    this.qMax,
    this.isQClamped = false,
  });

  /// 1-based bus index
  final int busNumber;

  /// Display name (e.g. "Bus 1 (Slack)")
  final String name;

  /// Bus classification: Slack, PV, or PQ
  final BusType type;

  /// Center anchor coordinate on the virtual diagram canvas
  final Offset position;

  /// Whether the busbar line is rendered vertically or horizontally
  final bool isVertical;

  /// Length of the busbar line in canvas pixels
  final double length;

  /// Real-time or specified voltage magnitude in per unit
  final double vMag;

  /// Voltage phase angle in degrees
  final double angleDeg;

  /// Active power generation (pu)
  final double pGen;

  /// Reactive power generation (pu)
  final double qGen;

  /// Active load demand (pu)
  final double pLoad;

  /// Reactive load demand (pu)
  final double qLoad;

  /// Reactive power generation lower bound (pu), applicable for PV buses
  final double? qMin;

  /// Reactive power generation upper bound (pu), applicable for PV buses
  final double? qMax;

  /// Whether a PV bus has reached Qmin or Qmax and was clamped to a PQ bus
  final bool isQClamped;

  /// Net real power injection: P_net = P_G - P_L (pu)
  double get pNet => pGen - pLoad;

  /// Net reactive power injection: Q_net = Q_G - Q_L (pu)
  double get qNet => qGen - qLoad;

  /// True if a generator is connected to this bus
  bool get hasGenerator =>
      type == BusType.slack || type == BusType.pv || pGen > 1e-4;

  /// True if a load is connected to this bus
  bool get hasLoad => pLoad > 1e-4 || qLoad.abs() > 1e-4;

  /// Start point of the busbar line
  Offset get startPoint {
    final half = length / 2.0;
    return isVertical
        ? Offset(position.dx, position.dy - half)
        : Offset(position.dx - half, position.dy);
  }

  /// End point of the busbar line
  Offset get endPoint {
    final half = length / 2.0;
    return isVertical
        ? Offset(position.dx, position.dy + half)
        : Offset(position.dx + half, position.dy);
  }

  /// Bounding rectangle for the busbar including comfortable touch padding
  Rect get hitBounds {
    const padding = 28.0;
    final half = length / 2.0;
    if (isVertical) {
      return Rect.fromLTRB(
        position.dx - padding,
        position.dy - half - padding,
        position.dx + padding,
        position.dy + half + padding,
      );
    } else {
      return Rect.fromLTRB(
        position.dx - half - padding,
        position.dy - padding,
        position.dx + half + padding,
        position.dy + padding,
      );
    }
  }

  /// Generator symbol anchor center
  Offset get generatorAnchor {
    // If bus is horizontal, generator sits 48px above
    // If vertical, generator sits 48px to the left
    return isVertical
        ? Offset(position.dx - 48.0, position.dy)
        : Offset(position.dx, position.dy - 48.0);
  }

  /// Load symbol anchor center
  Offset get loadAnchor {
    // If bus is horizontal, load sits 48px below
    // If vertical, load sits 48px to the right
    return isVertical
        ? Offset(position.dx + 48.0, position.dy)
        : Offset(position.dx, position.dy + 48.0);
  }

  /// Checks if a canvas tap falls within this busbar or its attached components
  bool hitTest(Offset tapPos) {
    if (hitBounds.contains(tapPos)) return true;
    if (hasGenerator) {
      final genDist = (tapPos - generatorAnchor).distance;
      if (genDist <= 28.0) return true;
    }
    if (hasLoad) {
      final loadDist = (tapPos - loadAnchor).distance;
      if (loadDist <= 28.0) return true;
    }
    return false;
  }

  SldBusNode copyWith({
    int? busNumber,
    String? name,
    BusType? type,
    Offset? position,
    bool? isVertical,
    double? length,
    double? vMag,
    double? angleDeg,
    double? pGen,
    double? qGen,
    double? pLoad,
    double? qLoad,
    double? Function()? qMin,
    double? Function()? qMax,
    bool? isQClamped,
  }) {
    return SldBusNode(
      busNumber: busNumber ?? this.busNumber,
      name: name ?? this.name,
      type: type ?? this.type,
      position: position ?? this.position,
      isVertical: isVertical ?? this.isVertical,
      length: length ?? this.length,
      vMag: vMag ?? this.vMag,
      angleDeg: angleDeg ?? this.angleDeg,
      pGen: pGen ?? this.pGen,
      qGen: qGen ?? this.qGen,
      pLoad: pLoad ?? this.pLoad,
      qLoad: qLoad ?? this.qLoad,
      qMin: qMin != null ? qMin() : this.qMin,
      qMax: qMax != null ? qMax() : this.qMax,
      isQClamped: isQClamped ?? this.isQClamped,
    );
  }
}
