import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/math/power_flow_common.dart';
import '../models/sld_bus_node.dart';
import '../models/sld_line_branch.dart';

/// High-performance CustomPainter rendering the power system single-line diagram.
class SldGridPainter extends CustomPainter {
  SldGridPainter({
    required this.buses,
    required this.lines,
    this.selectedBusNumber,
    this.selectedLineId,
    this.connectingFromBusNumber,
    this.liveConnectPoint,
    required this.isDark,
    required this.colorScheme,
    this.showPowerFlowBadges = true,
    this.showDirectionArrows = true,
    this.showVoltages = true,
    this.showLosses = true,
    this.mvaBase = 100.0,
    this.flowAnimationValue = 0.0,
    this.flowAnimation,
    this.transformMatrix,
    this.visibleSceneRect,
    super.repaint,
  });

  final List<SldBusNode> buses;
  final List<SldLineBranch> lines;
  final int? selectedBusNumber;
  final String? selectedLineId;
  final int? connectingFromBusNumber;
  final Offset? liveConnectPoint;
  final bool isDark;
  final ColorScheme colorScheme;
  final bool showPowerFlowBadges;
  final bool showDirectionArrows;
  final bool showVoltages;
  final bool showLosses;
  final double mvaBase;
  final double flowAnimationValue;
  final Animation<double>? flowAnimation;
  final Matrix4? transformMatrix;
  final Rect? visibleSceneRect;

  // Engineering theme colors
  Color get _gridMajorColor =>
      isDark ? const Color(0x1F4FC3F7) : const Color(0x150F3A66);
  Color get _gridMinorColor =>
      isDark ? const Color(0x0CFFFFFF) : const Color(0x0A000000);
  Color get _lineColor =>
      isDark ? const Color(0xFF90CAF9) : const Color(0xFF1E3A8A);
  Color get _selectedColor =>
      isDark ? const Color(0xFF00E5FF) : const Color(0xFF2563EB);

  // Bus type theme colors
  static const Color colorSlack = Color(0xFF7C4DFF); // Deep Purple Accent
  static const Color colorPv = Color(0xFFFF9100);    // Bright Amber / Orange
  static const Color colorPq = Color(0xFF00B0FF);    // Electric Light Blue

  static Rect computeSceneRect(Size viewportSize, Matrix4 matrix) {
    final inverse = Matrix4.tryInvert(matrix);
    if (inverse == null) {
      return Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height);
    }
    final p0 = MatrixUtils.transformPoint(inverse, Offset.zero);
    final p1 = MatrixUtils.transformPoint(inverse, Offset(viewportSize.width, 0));
    final p2 = MatrixUtils.transformPoint(inverse, Offset(0, viewportSize.height));
    final p3 = MatrixUtils.transformPoint(inverse, Offset(viewportSize.width, viewportSize.height));

    final minX = math.min(math.min(p0.dx, p1.dx), math.min(p2.dx, p3.dx));
    final maxX = math.max(math.max(p0.dx, p1.dx), math.max(p2.dx, p3.dx));
    final minY = math.min(math.min(p0.dy, p1.dy), math.min(p2.dy, p3.dy));
    final maxY = math.max(math.max(p0.dy, p1.dy), math.max(p2.dy, p3.dy));

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (transformMatrix != null) {
      canvas.save();
      canvas.transform(transformMatrix!.storage);
    }

    // 1. Draw blueprint grid background covering visible scene rect or viewport
    final gridRect = visibleSceneRect ??
        (transformMatrix != null
            ? computeSceneRect(size, transformMatrix!)
            : Rect.fromLTWH(0, 0, size.width, size.height));
    _drawBlueprintGrid(canvas, gridRect);

    // Map bus numbers to their SldBusNode for quick coordinate lookup
    final busMap = <int, SldBusNode>{};
    for (final bus in buses) {
      busMap[bus.busNumber] = bus;
    }

    // 2. Draw transmission lines and transformers
    for (final line in lines) {
      final fromBus = busMap[line.fromBus];
      final toBus = busMap[line.toBus];
      if (fromBus == null || toBus == null) continue;

      final isSelected = line.id == selectedLineId;
      _drawBranch(canvas, line, fromBus, toBus, isSelected);
    }

    // 2b. Draw dynamic rubber-band wire if user is currently connecting buses
    if (connectingFromBusNumber != null && liveConnectPoint != null) {
      final source = busMap[connectingFromBusNumber];
      if (source != null) {
        _drawLiveConnectionLine(canvas, source.position, liveConnectPoint!);
      }
    }

    // 3. Draw busbars and attached network elements (generators, loads)
    for (final bus in buses) {
      final isSelected = bus.busNumber == selectedBusNumber;
      _drawBusbar(canvas, bus, isSelected);
    }

    if (transformMatrix != null) {
      canvas.restore();
    }
  }

  void _drawLiveConnectionLine(Canvas canvas, Offset start, Offset end) {
    final glowPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.35)
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, glowPaint);
    canvas.drawLine(start, end, linePaint);

    // Reticle at current cursor point
    final reticlePaint = Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(end, 4.5, reticlePaint);
  }

  /// Draws a clean engineering blueprint grid across the visible canvas area
  void _drawBlueprintGrid(Canvas canvas, Rect visibleRect) {
    final minorPaint = Paint()
      ..color = _gridMinorColor
      ..strokeWidth = 1.0;

    final majorPaint = Paint()
      ..color = _gridMajorColor
      ..strokeWidth = 1.2;

    const minorStep = 25.0;
    const majorStep = 100.0;

    // Expand bounds slightly to prevent visual seam gaps at screen edges
    final minX = (visibleRect.left / minorStep).floor() * minorStep - minorStep;
    final maxX = (visibleRect.right / minorStep).ceil() * minorStep + minorStep;
    final minY = (visibleRect.top / minorStep).floor() * minorStep - minorStep;
    final maxY = (visibleRect.bottom / minorStep).ceil() * minorStep + minorStep;

    // Minor grid lines
    for (double x = minX; x <= maxX; x += minorStep) {
      canvas.drawLine(Offset(x, minY), Offset(x, maxY), minorPaint);
    }
    for (double y = minY; y <= maxY; y += minorStep) {
      canvas.drawLine(Offset(minX, y), Offset(maxX, y), minorPaint);
    }

    // Major grid lines
    final majorMinX = (visibleRect.left / majorStep).floor() * majorStep - majorStep;
    final majorMaxX = (visibleRect.right / majorStep).ceil() * majorStep + majorStep;
    final majorMinY = (visibleRect.top / majorStep).floor() * majorStep - majorStep;
    final majorMaxY = (visibleRect.bottom / majorStep).ceil() * majorStep + majorStep;

    for (double x = majorMinX; x <= majorMaxX; x += majorStep) {
      canvas.drawLine(Offset(x, majorMinY), Offset(x, majorMaxY), majorPaint);
    }
    for (double y = majorMinY; y <= majorMaxY; y += majorStep) {
      canvas.drawLine(Offset(majorMinX, y), Offset(majorMaxX, y), majorPaint);
    }

    // Subtle origin crosshair marker at (0, 0)
    final originPaint = Paint()
      ..color = isDark ? const Color(0x334FC3F7) : const Color(0x250F3A66)
      ..strokeWidth = 2.0;
    if (minX <= 0 && maxX >= 0) {
      canvas.drawLine(Offset(0, minY), Offset(0, maxY), originPaint);
    }
    if (minY <= 0 && maxY >= 0) {
      canvas.drawLine(Offset(minX, 0), Offset(maxX, 0), originPaint);
    }
  }

  /// Draws a transmission line branch with optional flow arrows and badges
  void _drawBranch(
    Canvas canvas,
    SldLineBranch line,
    SldBusNode fromBus,
    SldBusNode toBus,
    bool isSelected,
  ) {
    final start = fromBus.position;
    final end = toBus.position;

    final linePaint = Paint()
      ..color = isSelected ? _selectedColor : _lineColor
      ..strokeWidth = isSelected ? 4.0 : 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Halo glow if selected
    if (isSelected) {
      final haloPaint = Paint()
        ..color = _selectedColor.withValues(alpha: 0.3)
        ..strokeWidth = 9.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, haloPaint);
    }

    // Main line segment
    canvas.drawLine(start, end, linePaint);

    final midPoint = Offset((start.dx + end.dx) / 2.0, (start.dy + end.dy) / 2.0);

    // If transformer, draw IEEE two interlocking circles symbol
    if (line.isTransformer) {
      _drawTransformerSymbol(canvas, midPoint, isSelected);
    }

    // Flow direction arrow and animated power packets
    final pFlow = line.pFromTo;
    if (showDirectionArrows && pFlow.abs() > 0.001) {
      final isForward = pFlow > 0;
      final arrowSource = isForward ? start : end;
      final arrowTarget = isForward ? end : start;
      _drawFlowArrow(canvas, arrowSource, arrowTarget, midPoint);
      _drawAnimatedPowerFlow(canvas, arrowSource, arrowTarget, pFlow.abs());
    }

    // Floating line power flow badge
    if (showPowerFlowBadges && (line.sFromTo != null || line.sToFrom != null)) {
      _drawFlowBadge(canvas, line, midPoint, start, end);
    }
  }

  /// Draws animated electrical energy packets flowing along the branch in the direction of power
  void _drawAnimatedPowerFlow(
    Canvas canvas,
    Offset from,
    Offset to,
    double pFlowMag,
  ) {
    final dist = (to - from).distance;
    if (dist < 36.0) return;

    // Number of flowing particles scales with line length (2 to 5 particles)
    final particleCount = (dist / 85.0).clamp(2, 5).toInt();
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);

    final currentFlowValue = flowAnimation?.value ?? flowAnimationValue;
    for (int i = 0; i < particleCount; i++) {
      final phase = i / particleCount;
      // Loop phase seamlessly
      final t = (currentFlowValue + phase) % 1.0;

      // Smooth fade out near the terminal ends of the branch so particles don't abruptly pop
      final fade = math.sin(t * math.pi);
      if (fade <= 0.04) continue;

      final pos = Offset(
        from.dx + (to.dx - from.dx) * t,
        from.dy + (to.dy - from.dy) * t,
      );

      // Trailing comet tail behind the packet
      final tailLength = (12.0 * fade).clamp(4.0, 14.0);
      final tailEnd = Offset(
        pos.dx - tailLength * math.cos(angle),
        pos.dy - tailLength * math.sin(angle),
      );

      final tailPaint = Paint()
        ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
            .withValues(alpha: 0.45 * fade)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(tailEnd, pos, tailPaint);

      // Outer soft glow
      final glowPaint = Paint()
        ..color = (isDark ? const Color(0xFF00E5FF) : const Color(0xFF0284C7))
            .withValues(alpha: 0.35 * fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 5.5, glowPaint);

      // Middle ring
      final midPaint = Paint()
        ..color = (isDark ? const Color(0xFF67E8F9) : const Color(0xFF38BDF8))
            .withValues(alpha: 0.75 * fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 3.2, midPaint);

      // Bright incandescent core
      final corePaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.95 * fade)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 1.6, corePaint);
    }
  }

  /// Draws IEEE two overlapping circles symbol for transformers
  void _drawTransformerSymbol(Canvas canvas, Offset center, bool isSelected) {
    final xfmrPaint = Paint()
      ..color = isSelected ? _selectedColor : (isDark ? Colors.cyanAccent : Colors.teal)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : Colors.white
      ..style = PaintingStyle.fill;

    const r = 9.0;
    final c1 = Offset(center.dx - 5.0, center.dy);
    final c2 = Offset(center.dx + 5.0, center.dy);

    canvas.drawCircle(c1, r, fillPaint);
    canvas.drawCircle(c1, r, xfmrPaint);
    canvas.drawCircle(c2, r, fillPaint);
    canvas.drawCircle(c2, r, xfmrPaint);
  }

  /// Draws a directional arrowhead showing active power transfer direction
  void _drawFlowArrow(Canvas canvas, Offset from, Offset to, Offset midPoint) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const arrowLength = 10.0;
    const arrowAngle = math.pi / 6.0;

    // Position arrow at 40% of branch length so it doesn't clash with center badge
    final pos = Offset(
      from.dx + (to.dx - from.dx) * 0.38,
      from.dy + (to.dy - from.dy) * 0.38,
    );

    final arrowPaint = Paint()
      ..color = isDark ? const Color(0xFF69F0AE) : const Color(0xFF10B981)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(pos.dx, pos.dy)
      ..lineTo(
        pos.dx - arrowLength * math.cos(angle - arrowAngle),
        pos.dy - arrowLength * math.sin(angle - arrowAngle),
      )
      ..lineTo(
        pos.dx - (arrowLength * 0.6) * math.cos(angle),
        pos.dy - (arrowLength * 0.6) * math.sin(angle),
      )
      ..lineTo(
        pos.dx - arrowLength * math.cos(angle + arrowAngle),
        pos.dy - arrowLength * math.sin(angle + arrowAngle),
      )
      ..close();

    canvas.drawPath(path, arrowPaint);
  }

  /// Draws floating active/reactive flow and loss badge on branch
  void _drawFlowBadge(
    Canvas canvas,
    SldLineBranch line,
    Offset midPoint,
    Offset start,
    Offset end,
  ) {
    final pMW = line.pFromTo * mvaBase;
    final qMvar = line.qFromTo * mvaBase;
    final pLossMW = line.pLoss * mvaBase;

    String text = '${pMW.toStringAsFixed(1)} MW, ${qMvar.toStringAsFixed(1)} MVAR';
    if (showLosses && pLossMW > 0.01) {
      text += ' (L: ${pLossMW.toStringAsFixed(1)})';
    }

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    // Offset badge slightly perpendicular to line
    final lineAngle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final perpAngle = lineAngle + math.pi / 2.0;
    const badgeOffsetDist = 18.0;

    final badgeCenter = Offset(
      midPoint.dx + badgeOffsetDist * math.cos(perpAngle),
      midPoint.dy + badgeOffsetDist * math.sin(perpAngle),
    );

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: badgeCenter,
        width: textPainter.width + 12.0,
        height: textPainter.height + 6.0,
      ),
      const Radius.circular(6),
    );

    final bgPaint = Paint()
      ..color = isDark
          ? const Color(0xE60F172A)
          : const Color(0xF2FFFFFF)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(badgeRect, bgPaint);
    canvas.drawRRect(badgeRect, borderPaint);

    textPainter.paint(
      canvas,
      Offset(
        badgeCenter.dx - textPainter.width / 2.0,
        badgeCenter.dy - textPainter.height / 2.0,
      ),
    );
  }

  /// Draws a busbar along with attached machine and load symbols
  void _drawBusbar(Canvas canvas, SldBusNode bus, bool isSelected) {
    final busColor = switch (bus.type) {
      BusType.slack => colorSlack,
      BusType.pv => bus.isQClamped ? Colors.deepOrangeAccent : colorPv,
      BusType.pq => colorPq,
    };

    // Busbar main stroke
    final busPaint = Paint()
      ..color = busColor
      ..strokeWidth = 7.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final start = bus.startPoint;
    final end = bus.endPoint;

    // Glowing halo if selected
    if (isSelected) {
      final glowPaint = Paint()
        ..color = busColor.withValues(alpha: 0.35)
        ..strokeWidth = 17.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, glowPaint);
    }

    // Highlight ring if currently being connected
    if (bus.busNumber == connectingFromBusNumber) {
      final pulsePaint = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(bus.position, 28.0, pulsePaint);
    }

    canvas.drawLine(start, end, busPaint);

    // Bus ID & Type badge
    _drawBusBadge(canvas, bus, busColor);

    // Generator connection
    if (bus.hasGenerator) {
      _drawGeneratorSymbol(canvas, bus, busColor);
    }

    // Load connection
    if (bus.hasLoad) {
      _drawLoadSymbol(canvas, bus);
    }
  }

  /// Draws bus label and live voltage badge
  void _drawBusBadge(Canvas canvas, SldBusNode bus, Color busColor) {
    final typeStr = switch (bus.type) {
      BusType.slack => 'SLACK',
      BusType.pv => bus.isQClamped ? 'PV (CLAMPED)' : 'PV',
      BusType.pq => 'PQ',
    };

    final titleText = 'Bus ${bus.busNumber} [$typeStr]';
    final vText = showVoltages
        ? '${bus.vMag.toStringAsFixed(3)} pu ∠${bus.angleDeg.toStringAsFixed(1)}°'
        : '';

    final textSpan = TextSpan(
      children: [
        TextSpan(
          text: '$titleText\n',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: busColor,
          ),
        ),
        if (showVoltages)
          TextSpan(
            text: vText,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
      ],
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    // Position text above horizontal bus or to the side of vertical bus
    final textPos = bus.isVertical
        ? Offset(bus.position.dx + 16.0, bus.position.dy - textPainter.height / 2.0)
        : Offset(bus.position.dx - textPainter.width / 2.0, bus.position.dy - 34.0);

    textPainter.paint(canvas, textPos);
  }

  /// Draws standard IEEE circular machine symbol for generators
  void _drawGeneratorSymbol(Canvas canvas, SldBusNode bus, Color busColor) {
    final center = bus.generatorAnchor;
    final tieStart = bus.position;

    // Tie connection line
    final tiePaint = Paint()
      ..color = busColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tieStart, center, tiePaint);

    const radius = 17.0;

    final fillPaint = Paint()
      ..color = isDark ? const Color(0xFF1E293B) : Colors.white
      ..style = PaintingStyle.fill;

    final circlePaint = Paint()
      ..color = busColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, circlePaint);

    // Sine wave '~' inside circle
    final wavePaint = Paint()
      ..color = busColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final wavePath = Path();
    const w = 9.0;
    wavePath.moveTo(center.dx - w, center.dy);
    wavePath.quadraticBezierTo(
      center.dx - w / 2.0, center.dy - 6.0,
      center.dx, center.dy,
    );
    wavePath.quadraticBezierTo(
      center.dx + w / 2.0, center.dy + 6.0,
      center.dx + w, center.dy,
    );
    canvas.drawPath(wavePath, wavePaint);

    // Generator active generation badge
    final pGenMW = bus.pGen * mvaBase;
    if (pGenMW > 0.1 || bus.type == BusType.slack) {
      final genSpan = TextSpan(
        text: 'P_G: ${pGenMW.toStringAsFixed(1)} MW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          color: busColor,
        ),
      );
      final genPainter = TextPainter(
        text: genSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      genPainter.paint(
        canvas,
        Offset(center.dx - genPainter.width / 2.0, center.dy - radius - 14.0),
      );
    }
  }

  /// Draws IEEE arrow/box load symbol
  void _drawLoadSymbol(Canvas canvas, SldBusNode bus) {
    final anchor = bus.loadAnchor;
    final tieStart = bus.position;

    const loadColor = Color(0xFFE53935); // Engineering Red for consumers

    // Stiff lead tie
    final tiePaint = Paint()
      ..color = loadColor
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(tieStart, anchor, tiePaint);

    // Downward arrow
    final arrowPaint = Paint()
      ..color = loadColor
      ..style = PaintingStyle.fill;

    const arrowWidth = 14.0;
    const arrowHeight = 16.0;

    final arrowPath = Path()
      ..moveTo(anchor.dx, anchor.dy + arrowHeight)
      ..lineTo(anchor.dx - arrowWidth / 2.0, anchor.dy)
      ..lineTo(anchor.dx + arrowWidth / 2.0, anchor.dy)
      ..close();

    canvas.drawPath(arrowPath, arrowPaint);

    // Load active/reactive demand label
    final pLoadMW = bus.pLoad * mvaBase;
    final qLoadMvar = bus.qLoad * mvaBase;

    final textSpan = TextSpan(
      text: '${pLoadMW.toStringAsFixed(1)} MW\n${qLoadMvar.toStringAsFixed(1)} MVAR',
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        fontFamily: 'monospace',
        color: loadColor,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(anchor.dx - textPainter.width / 2.0, anchor.dy + arrowHeight + 4.0),
    );
  }

  @override
  bool shouldRepaint(covariant SldGridPainter oldDelegate) {
    return oldDelegate.buses != buses ||
        oldDelegate.lines != lines ||
        oldDelegate.selectedBusNumber != selectedBusNumber ||
        oldDelegate.selectedLineId != selectedLineId ||
        oldDelegate.connectingFromBusNumber != connectingFromBusNumber ||
        oldDelegate.liveConnectPoint != liveConnectPoint ||
        oldDelegate.isDark != isDark ||
        oldDelegate.showPowerFlowBadges != showPowerFlowBadges ||
        oldDelegate.showDirectionArrows != showDirectionArrows ||
        oldDelegate.showVoltages != showVoltages ||
        oldDelegate.showLosses != showLosses ||
        oldDelegate.transformMatrix != transformMatrix ||
        oldDelegate.visibleSceneRect != visibleSceneRect ||
        oldDelegate.flowAnimationValue != flowAnimationValue ||
        oldDelegate.flowAnimation != flowAnimation;
  }
}
