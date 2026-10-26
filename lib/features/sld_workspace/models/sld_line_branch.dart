import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/complex.dart';

/// Visual and electrical representation of a transmission line branch on the SLD canvas.
class SldLineBranch {
  const SldLineBranch({
    required this.id,
    required this.fromBus,
    required this.toBus,
    required this.r,
    required this.x,
    this.bHalf = 0.0,
    this.tap = 1.0,
    this.sFromTo,
    this.sToFrom,
    this.loss,
    this.waypoints = const [],
  });

  /// Unique branch identifier
  final String id;

  /// Sending bus number (1-based)
  final int fromBus;

  /// Receiving bus number (1-based)
  final int toBus;

  /// Resistance in per unit
  final double r;

  /// Reactance in per unit
  final double x;

  /// Total line charging shunt susceptance B/2 in per unit
  final double bHalf;

  /// Off-nominal transformer tap ratio (1.0 = standard transmission line)
  final double tap;

  /// Complex power flow at sending end S_ij = P_ij + j*Q_ij (pu)
  final Complex? sFromTo;

  /// Complex power flow at receiving end S_ji = P_ji + j*Q_ji (pu)
  final Complex? sToFrom;

  /// Total branch complex losses S_Lij = S_ij + S_ji (pu)
  final Complex? loss;

  /// Optional intermediate waypoints for orthogonal routing bends
  final List<Offset> waypoints;

  /// Active power flow from sending to receiving end (pu)
  double get pFromTo => sFromTo?.re ?? 0.0;

  /// Reactive power flow from sending to receiving end (pu)
  double get qFromTo => sFromTo?.im ?? 0.0;

  /// Active power flow from receiving to sending end (pu)
  double get pToFrom => sToFrom?.re ?? 0.0;

  /// Reactive power flow from receiving to sending end (pu)
  double get qToFrom => sToFrom?.im ?? 0.0;

  /// Real power loss on branch (pu)
  double get pLoss => loss?.re ?? (sFromTo != null && sToFrom != null ? (sFromTo! + sToFrom!).re : 0.0);

  /// Reactive power loss on branch (pu)
  double get qLoss => loss?.im ?? (sFromTo != null && sToFrom != null ? (sFromTo! + sToFrom!).im : 0.0);

  /// True if branch is a transformer (tap != 1.0 or pure reactance with no charging)
  bool get isTransformer => (tap - 1.0).abs() > 1e-4;

  /// Series impedance Z = R + jX
  Complex get seriesImpedance => Complex(r, x);

  /// Magnitude of impedance |Z|
  double get zMagnitude => math.sqrt(r * r + x * x);

  /// Checks if a tap is near the transmission line polyline
  bool hitTest(Offset tapPos, Offset fromAnchor, Offset toAnchor, {double touchMargin = 16.0}) {
    final points = [fromAnchor, ...waypoints, toAnchor];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final dist = _distanceToSegment(tapPos, a, b);
      if (dist <= touchMargin) {
        return true;
      }
    }
    return false;
  }

  /// Calculates shortest distance from point p to line segment a-b
  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 1e-6) {
      return (p - a).distance;
    }

    final t = (((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq).clamp(0.0, 1.0);
    final projection = Offset(a.dx + t * dx, a.dy + t * dy);
    return (p - projection).distance;
  }

  SldLineBranch copyWith({
    String? id,
    int? fromBus,
    int? toBus,
    double? r,
    double? x,
    double? bHalf,
    double? tap,
    Complex? Function()? sFromTo,
    Complex? Function()? sToFrom,
    Complex? Function()? loss,
    List<Offset>? waypoints,
  }) {
    return SldLineBranch(
      id: id ?? this.id,
      fromBus: fromBus ?? this.fromBus,
      toBus: toBus ?? this.toBus,
      r: r ?? this.r,
      x: x ?? this.x,
      bHalf: bHalf ?? this.bHalf,
      tap: tap ?? this.tap,
      sFromTo: sFromTo != null ? sFromTo() : this.sFromTo,
      sToFrom: sToFrom != null ? sToFrom() : this.sToFrom,
      loss: loss != null ? loss() : this.loss,
      waypoints: waypoints ?? this.waypoints,
    );
  }
}
