import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../economic_dispatch/providers/economic_dispatch_provider.dart';
import '../providers/ems_console_provider.dart';
import 'widgets/frequency_transient_chart.dart';
import 'widgets/lambda_curve_chart.dart';

/// EMS / SCADA Dynamic Dispatch and Visualization Console modeling control room operations.
class EmsDashboardScreen extends ConsumerWidget {
  const EmsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final emsState = ref.watch(emsConsoleProvider);
    final emsNotifier = ref.read(emsConsoleProvider.notifier);
    final edState = ref.watch(economicDispatchProvider);

    // Build map of dispatched generator powers
    final dispatchedMap = <String, double>{};
    if (edState.losslessResult != null) {
      dispatchedMap.addAll(edState.losslessResult!.powers);
    } else if (edState.lossResult != null) {
      dispatchedMap.addAll(edState.lossResult!.powers);
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.analytics_outlined, color: Colors.tealAccent),
            const SizedBox(width: 10),
            Text(
              'EMS / SCADA Dispatch Console',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'TELEMETRY LIVE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. System Summary Metric Ribbon
          _buildMetricRibbon(emsState, theme, isDark),

          const SizedBox(height: 16),

          // 2. Area Control Error (ACE) Gauge Card
          _buildAceGaugeCard(emsState, theme, isDark),

          const SizedBox(height: 16),

          // 3. Dynamic LFC Step-Response Transient Simulator
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.speed, color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Dynamic LFC Transient Simulator',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'RK4 ODE SOLVER',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simulates closed-loop turbine-governor frequency response under step disturbance ΔP_L. Compare steady-state primary droop with secondary AGC restoration.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  FrequencyTransientChart(
                    params: emsState.dynamicParams,
                    onParamsChanged: (newParams) {
                      emsNotifier.updateDynamicParams(newParams);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 4. Equal Incremental Fuel Cost (Lambda) Visualizer
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Equal Incremental Fuel Cost: ICR_i(P_i) = λ',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'λ = ${emsState.systemLambda.toStringAsFixed(4)} \$/MWh',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Thermal unit operating points cleared at system marginal cost λ. Markers turn red when a unit hits its lower/upper active power boundary.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  LambdaCurveChart(
                    units: edState.units,
                    lambda: emsState.systemLambda,
                    dispatchedPowers: dispatchedMap,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// System Summary Metric Ribbon displaying core transmission grid state
  Widget _buildMetricRibbon(EmsConsoleState state, ThemeData theme, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 32) / 3.0;
        final isNarrow = constraints.maxWidth < 600;

        final items = [
          _ribbonCard(
            label: 'Total Generation',
            value: '${state.totalGenMW.toStringAsFixed(1)} MW',
            subValue: '${state.totalGenMvar.toStringAsFixed(1)} MVAR',
            icon: Icons.electric_bolt,
            iconColor: const Color(0xFF10B981),
            isDark: isDark,
          ),
          _ribbonCard(
            label: 'Total Load Demand',
            value: '${state.totalLoadMW.toStringAsFixed(1)} MW',
            subValue: '${state.totalLoadMvar.toStringAsFixed(1)} MVAR',
            icon: Icons.domain,
            iconColor: const Color(0xFF3B82F6),
            isDark: isDark,
          ),
          _ribbonCard(
            label: 'Transmission Losses',
            value: '${state.totalLossMW.toStringAsFixed(2)} MW',
            subValue: '${state.totalLossMvar.toStringAsFixed(2)} MVAR',
            icon: Icons.trending_down,
            iconColor: const Color(0xFFEF4444),
            isDark: isDark,
          ),
          _ribbonCard(
            label: 'System Incremental Cost',
            value: state.systemLambda.toStringAsFixed(3),
            subValue: '\$/MWh marginal',
            icon: Icons.price_change,
            iconColor: const Color(0xFFF59E0B),
            isDark: isDark,
          ),
          _ribbonCard(
            label: 'Grid Frequency',
            value: '${state.gridFrequencyHz.toStringAsFixed(3)} Hz',
            subValue: 'Δf = ${state.deltaFreqHz.toStringAsFixed(3)} Hz',
            icon: Icons.speed,
            iconColor: state.deltaFreqHz.abs() > 0.1 ? Colors.orange : Colors.tealAccent,
            isDark: isDark,
          ),
        ];

        if (isNarrow) {
          return Column(
            children: items
                .map((w) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: w,
                    ))
                .toList(),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((w) => SizedBox(
                    width: cardWidth.clamp(160.0, 300.0),
                    child: w,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _ribbonCard({
    required String label,
    required String value,
    required String subValue,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  subValue,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Area Control Error (ACE) Gauge with color-coded threshold zones
  Widget _buildAceGaugeCard(EmsConsoleState state, ThemeData theme, bool isDark) {
    final severityColor = switch (state.aceSeverity) {
      AceSeverity.normal => const Color(0xFF10B981),
      AceSeverity.warning => const Color(0xFFF59E0B),
      AceSeverity.emergency => const Color(0xFFEF4444),
    };

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.tune, color: severityColor, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Area Control Error (ACE) Indicator',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    state.aceSeverity.title.toUpperCase(),
                    style: TextStyle(
                      color: severityColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'ACE = ΔP_tie + B · Δf  — measures the active power interchange and frequency imbalance required for secondary AGC regulation.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),

            // ACE Large Value Display & Breakdown
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${state.aceMW.toStringAsFixed(2)} MW',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: severityColor,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _aceComponentPill(
                          label: 'Tie-Line ΔP_tie',
                          value: '${state.deltaPtieMW.toStringAsFixed(2)} MW',
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _aceComponentPill(
                          label: 'Freq Bias B·Δf',
                          value: '${state.freqBiasMW.toStringAsFixed(2)} MW',
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Visual Gauge Bar
            _buildAceVisualBar(state.aceMW, isDark),

            const SizedBox(height: 8),

            // Gauge scale legend (-30 MW ... 0 ... +30 MW)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-30 MW', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Text('-20 MW [WARN]', style: TextStyle(fontSize: 10, color: Colors.amber.shade700)),
                Text('-5 MW', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                const Text('0 MW (BALANCED)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('+5 MW', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                Text('+20 MW [WARN]', style: TextStyle(fontSize: 10, color: Colors.amber.shade700)),
                Text('+30 MW', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _aceComponentPill({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(height: 1),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  /// Segmented visual gauge bar with indicator pointer
  Widget _buildAceVisualBar(double aceMW, bool isDark) {
    // Range is -30 MW to +30 MW (normalized 0.0 to 1.0)
    const minVal = -30.0;
    const maxVal = 30.0;
    final normalized = ((aceMW - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final pinPos = (normalized * totalWidth).clamp(6.0, totalWidth - 6.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Colored zone background bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    // Emergency left (-30 to -20 MW) -> 10/60
                    Expanded(flex: 10, child: Container(color: Colors.red.shade400)),
                    // Warning left (-20 to -5 MW) -> 15/60
                    Expanded(flex: 15, child: Container(color: Colors.amber.shade400)),
                    // Normal center (-5 to +5 MW) -> 10/60
                    Expanded(flex: 10, child: Container(color: Colors.green.shade500)),
                    // Warning right (+5 to +20 MW) -> 15/60
                    Expanded(flex: 15, child: Container(color: Colors.amber.shade400)),
                    // Emergency right (+20 to +30 MW) -> 10/60
                    Expanded(flex: 10, child: Container(color: Colors.red.shade400)),
                  ],
                ),
              ),
            ),

            // Needle indicator pin
            Positioned(
              left: pinPos - 6,
              top: -4,
              child: Container(
                width: 12,
                height: 24,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 2,
                    height: 16,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
