import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/math/economic_dispatch/generator_model.dart';

/// Interactive 2D Line Chart displaying equal incremental fuel cost curves ICR_i(P_i) = beta_i + 2*gamma_i*P_i
/// with dynamic system lambda reference and generator operating point markers.
class LambdaCurveChart extends StatelessWidget {
  const LambdaCurveChart({
    super.key,
    required this.units,
    required this.lambda,
    required this.dispatchedPowers,
    this.height = 340.0,
  });

  final List<GeneratorUnit> units;
  final double lambda;
  final Map<String, double> dispatchedPowers;
  final double height;

  static const List<Color> _unitColors = [
    Color(0xFF2563EB), // Blue
    Color(0xFF059669), // Emerald
    Color(0xFFD97706), // Amber
    Color(0xFF7C3AED), // Purple
    Color(0xFFDC2626), // Red
    Color(0xFF0891B2), // Cyan
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (units.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No thermal units configured.')),
      );
    }

    double maxP = 100.0;
    double maxIcr = lambda + 2.0;

    final lineBars = <LineChartBarData>[];

    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      if (!u.isActive) continue;

      final color = _unitColors[i % _unitColors.length];
      if (u.pMax > maxP) maxP = u.pMax;

      final spots = <FlSpot>[];
      const steps = 15;
      final stepSize = (u.pMax - u.pMin) / steps;

      for (var s = 0; s <= steps; s++) {
        final p = u.pMin + s * stepSize;
        final icr = u.icrAt(p);
        if (icr > maxIcr) maxIcr = icr;
        spots.add(FlSpot(p, icr));
      }

      lineBars.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 3.0,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, barData) {
              // Show endpoints of unit capacity
              return spot == spots.first || spot == spots.last;
            },
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: 4,
                color: color,
                strokeWidth: 1.5,
                strokeColor: isDark ? Colors.black : Colors.white,
              );
            },
          ),
        ),
      );
    }

    // Operating points bar (scatter dots at (P_i, lambda or ICR))
    final opSpots = <FlSpot>[];
    for (var i = 0; i < units.length; i++) {
      final u = units[i];
      final pDisp = dispatchedPowers[u.id] ?? u.powerAtLambda(lambda).clamp(u.pMin, u.pMax);
      final icrDisp = u.icrAt(pDisp);
      opSpots.add(FlSpot(pDisp, icrDisp));
    }

    // Build chart data
    final chartData = LineChartData(
      minX: 0,
      maxX: (maxP * 1.1).ceilToDouble(),
      minY: 0,
      maxY: (maxIcr * 1.15).ceilToDouble(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        getDrawingHorizontalLine: (value) => FlLine(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
          strokeWidth: 1,
        ),
        getDrawingVerticalLine: (value) => FlLine(
          color: isDark ? const Color(0x1FFFFFFF) : const Color(0x14000000),
          strokeWidth: 1,
        ),
      ),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          axisNameWidget: const Text(
            'Generator Power Output P_Gi (MW)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          axisNameSize: 22,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 28,
            interval: (maxP / 5.0).clamp(50.0, 500.0),
            getTitlesWidget: (value, meta) => Text(
              value.toInt().toString(),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ),
        ),
        leftTitles: AxisTitles(
          axisNameWidget: const Text(
            r'Incremental Fuel Cost ICR ($/MWh)',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          axisNameSize: 24,
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            interval: (maxIcr / 5.0).clamp(2.0, 20.0),
            getTitlesWidget: (value, meta) => Text(
              value.toStringAsFixed(1),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      extraLinesData: ExtraLinesData(
        horizontalLines: [
          HorizontalLine(
            y: lambda,
            color: isDark ? Colors.cyanAccent : Colors.indigoAccent,
            strokeWidth: 2.0,
            dashArray: [6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: Alignment.topRight,
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: isDark ? Colors.cyanAccent : Colors.indigoAccent,
              ),
              labelResolver: (_) => 'Cleared λ = ${lambda.toStringAsFixed(4)} \$/MWh',
            ),
          ),
        ],
      ),
      lineBarsData: [
        ...lineBars,
        // Operating point markers
        LineChartBarData(
          spots: opSpots,
          showingIndicators: List.generate(opSpots.length, (i) => i),
          isCurved: false,
          color: Colors.transparent,
          barWidth: 0,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              final u = units[index];
              final isAtMin = (spot.x - u.pMin).abs() < 1e-2;
              final isAtMax = (spot.x - u.pMax).abs() < 1e-2;
              final isBound = isAtMin || isAtMax;

              return FlDotCirclePainter(
                radius: isBound ? 7.0 : 6.0,
                color: isBound ? Colors.redAccent : Colors.amber,
                strokeWidth: 2.5,
                strokeColor: isDark ? Colors.black : Colors.white,
              );
            },
          ),
        ),
      ],
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => isDark ? const Color(0xFF1E293B) : Colors.white,
          getTooltipItems: (touchedSpots) {
            return touchedSpots.map((spot) {
              if (spot.barIndex < units.length) {
                final u = units[spot.barIndex];
                return LineTooltipItem(
                  '${u.name}\n${spot.x.toStringAsFixed(1)} MW @ ${spot.y.toStringAsFixed(3)} \$/MWh',
                  TextStyle(
                    color: _unitColors[spot.barIndex % _unitColors.length],
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                );
              }
              return null;
            }).toList();
          },
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend & Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: 12,
              children: [
                for (var i = 0; i < units.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _unitColors[i % _unitColors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        units[i].name,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Bound Clamped',
                  style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: height,
          child: LineChart(chartData),
        ),
      ],
    );
  }
}
