import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../engine/lfc_transient_engine.dart';
import '../../models/dynamic_lfc_params.dart';

enum LfcChartMode { primaryOnly, agcOnly, compareBoth }

/// Dynamic time-domain chart plotting grid frequency response f(t) / delta_f(t) over 0 to 30s
/// with toggle comparison between Primary Droop Only and Secondary Integral Action (AGC).
class FrequencyTransientChart extends StatefulWidget {
  const FrequencyTransientChart({
    super.key,
    required this.params,
    this.onParamsChanged,
  });

  final DynamicLfcParams params;
  final ValueChanged<DynamicLfcParams>? onParamsChanged;

  @override
  State<FrequencyTransientChart> createState() => _FrequencyTransientChartState();
}

class _FrequencyTransientChartState extends State<FrequencyTransientChart> {
  LfcChartMode _chartMode = LfcChartMode.compareBoth;
  bool _plotFrequencyNotDeviation = true; // True: f(t) in Hz, False: delta_f(t) in Hz
  bool _showSettings = false;

  late DynamicLfcParams _currentParams;

  @override
  void initState() {
    super.initState();
    _currentParams = widget.params;
  }

  @override
  void didUpdateWidget(covariant FrequencyTransientChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.params != widget.params) {
      _currentParams = widget.params;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Simulate curves using RK4
    final primaryTraj = LfcTransientEngine.simulate(
      params: _currentParams,
      enableAGC: false,
    );

    final agcTraj = LfcTransientEngine.simulate(
      params: _currentParams,
      enableAGC: true,
    );

    // Extract spots
    final primarySpots = <FlSpot>[];
    final agcSpots = <FlSpot>[];

    double minVal = 50.0;
    double maxVal = 50.0;

    for (final p in primaryTraj) {
      final y = _plotFrequencyNotDeviation ? p.frequency_Hz : p.deltaF_Hz;
      primarySpots.add(FlSpot(p.time, y));
      if (y < minVal) minVal = y;
      if (y > maxVal) maxVal = y;
    }

    for (final p in agcTraj) {
      final y = _plotFrequencyNotDeviation ? p.frequency_Hz : p.deltaF_Hz;
      agcSpots.add(FlSpot(p.time, y));
      if (y < minVal) minVal = y;
      if (y > maxVal) maxVal = y;
    }

    final double nominalY = _plotFrequencyNotDeviation ? _currentParams.nominalFreq : 0.0;
    final double ssY = _plotFrequencyNotDeviation
        ? _currentParams.steadyStateFreq_Hz
        : _currentParams.steadyStateDeltaF_Hz;

    final lineBars = <LineChartBarData>[];

    if (_chartMode == LfcChartMode.primaryOnly || _chartMode == LfcChartMode.compareBoth) {
      lineBars.add(
        LineChartBarData(
          spots: primarySpots,
          isCurved: true,
          curveSmoothness: 0.15,
          color: const Color(0xFFF59E0B), // Amber / Orange
          barWidth: 3.0,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    if (_chartMode == LfcChartMode.agcOnly || _chartMode == LfcChartMode.compareBoth) {
      lineBars.add(
        LineChartBarData(
          spots: agcSpots,
          isCurved: true,
          curveSmoothness: 0.15,
          color: const Color(0xFF10B981), // Emerald Green
          barWidth: 3.0,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    final yMargin = ((maxVal - minVal).abs() * 0.2).clamp(0.05, 0.5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode Selector & View Toggles
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SegmentedButton<LfcChartMode>(
              segments: const [
                ButtonSegment(
                  value: LfcChartMode.primaryOnly,
                  label: Text('Primary Droop', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: LfcChartMode.agcOnly,
                  label: Text('Secondary AGC', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: LfcChartMode.compareBoth,
                  label: Text('Compare Both', style: TextStyle(fontSize: 11)),
                ),
              ],
              selected: {_chartMode},
              onSelectionChanged: (val) {
                setState(() {
                  _chartMode = val.first;
                });
              },
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(_showSettings ? Icons.tune : Icons.tune_outlined),
                  tooltip: 'Tune LFC Parameters',
                  onPressed: () {
                    setState(() {
                      _showSettings = !_showSettings;
                    });
                  },
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _plotFrequencyNotDeviation = !_plotFrequencyNotDeviation;
                    });
                  },
                  icon: const Icon(Icons.swap_vert, size: 16),
                  label: Text(
                    _plotFrequencyNotDeviation ? 'f(t) [Hz]' : 'Δf(t) [Hz]',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Parameter tuning sliders panel
        if (_showSettings) ...[
          const SizedBox(height: 12),
          _buildParamSliders(isDark),
        ],

        const SizedBox(height: 12),

        // Chart
        SizedBox(
          height: 310,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: _currentParams.tMax,
              minY: (minVal - yMargin),
              maxY: (maxVal + yMargin),
              gridData: FlGridData(
                show: true,
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
                    'Time t (seconds)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  axisNameSize: 22,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 5.0,
                    getTitlesWidget: (val, meta) => Text(
                      '${val.toInt()}s',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Text(
                    _plotFrequencyNotDeviation ? 'Frequency f(t) (Hz)' : 'Deviation Δf(t) (Hz)',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  axisNameSize: 24,
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    interval: ((maxVal - minVal) / 4.0).clamp(0.02, 0.5),
                    getTitlesWidget: (val, meta) => Text(
                      val.toStringAsFixed(2),
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
                  // 50 Hz Nominal Reference
                  HorizontalLine(
                    y: nominalY,
                    color: Colors.grey,
                    strokeWidth: 1.5,
                    dashArray: [4, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                      labelResolver: (_) => _plotFrequencyNotDeviation ? ' Nominal 50.0 Hz' : ' 0.0 Hz',
                    ),
                  ),
                  // Steady-state offset without AGC
                  if (_chartMode != LfcChartMode.agcOnly)
                    HorizontalLine(
                      y: ssY,
                      color: Colors.amber.shade700,
                      strokeWidth: 1.2,
                      dashArray: [6, 3],
                      label: HorizontalLineLabel(
                        show: true,
                        alignment: Alignment.bottomRight,
                        style: TextStyle(fontSize: 10, color: Colors.amber.shade700),
                        labelResolver: (_) =>
                            ' Δf_ss = ${_currentParams.steadyStateDeltaF_Hz.toStringAsFixed(3)} Hz',
                      ),
                    ),
                ],
              ),
              lineBarsData: lineBars,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => isDark ? const Color(0xFF1E293B) : Colors.white,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final isAgc = spot.barIndex == 1 || (_chartMode == LfcChartMode.agcOnly);
                      final label = isAgc ? 'Secondary AGC' : 'Primary Droop';
                      return LineTooltipItem(
                        '$label\nt = ${spot.x.toStringAsFixed(1)}s\n${spot.y.toStringAsFixed(3)} Hz',
                        TextStyle(
                          color: isAgc ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // Legend & Notes
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (_chartMode != LfcChartMode.agcOnly)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 3,
                        color: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 4),
                      const Text('Primary Droop (offset)', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                if (_chartMode != LfcChartMode.primaryOnly)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 3,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      const Text('Secondary AGC (50.0 Hz)', style: TextStyle(fontSize: 11)),
                    ],
                  ),
              ],
            ),
            Text(
              'Step ΔP_L: ${_currentParams.stepLoadDeltaPL_MW.toStringAsFixed(0)} MW',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildParamSliders(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        children: [
          _sliderRow(
            label: 'Step Load Disturbance ΔP_L',
            value: _currentParams.stepLoadDeltaPL_MW,
            unit: 'MW',
            min: 10.0,
            max: 200.0,
            onChanged: (val) {
              setState(() {
                _currentParams = _currentParams.copyWith(stepLoadDeltaPL_MW: val);
              });
              widget.onParamsChanged?.call(_currentParams);
            },
          ),
          _sliderRow(
            label: 'System Inertia Constant H',
            value: _currentParams.inertiaH,
            unit: 's',
            min: 1.0,
            max: 10.0,
            onChanged: (val) {
              setState(() {
                _currentParams = _currentParams.copyWith(inertiaH: val);
              });
              widget.onParamsChanged?.call(_currentParams);
            },
          ),
          _sliderRow(
            label: 'Governor Speed Droop R',
            value: _currentParams.droopR * 100.0,
            unit: '%',
            min: 2.0,
            max: 10.0,
            onChanged: (val) {
              setState(() {
                _currentParams = _currentParams.copyWith(droopR: val / 100.0);
              });
              widget.onParamsChanged?.call(_currentParams);
            },
          ),
          _sliderRow(
            label: 'Secondary AGC Gain K_I',
            value: _currentParams.integralGainKi,
            unit: '',
            min: 0.05,
            max: 1.50,
            onChanged: (val) {
              setState(() {
                _currentParams = _currentParams.copyWith(integralGainKi: val);
              });
              widget.onParamsChanged?.call(_currentParams);
            },
          ),
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required String unit,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 170,
          child: Text(
            '$label:',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 65,
          child: Text(
            '${value.toStringAsFixed(2)} $unit',
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
