import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../economic_dispatch/providers/economic_dispatch_provider.dart';
import '../../load_frequency_control/providers/lfc_provider.dart';
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
    final lfcState = ref.watch(lfcProvider);

    // Build map of dispatched generator powers
    final dispatchedMap = <String, double>{};
    if (edState.losslessResult != null) {
      dispatchedMap.addAll(edState.losslessResult!.powers);
    } else if (edState.lossResult != null) {
      dispatchedMap.addAll(edState.lossResult!.powers);
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
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
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.analytics_outlined), text: 'SCADA Telemetry'),
              Tab(icon: Icon(Icons.school_outlined), text: 'Exam Step-by-Step'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTelemetryDashboard(
              context,
              ref,
              emsState,
              emsNotifier,
              edState,
              lfcState,
              dispatchedMap,
              theme,
              isDark,
            ),
            _buildEmsExamStepByStep(
              context,
              emsState,
              lfcState,
              edState,
              theme,
              isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryDashboard(
    BuildContext context,
    WidgetRef ref,
    EmsConsoleState emsState,
    EmsConsoleNotifier emsNotifier,
    EconomicDispatchState edState,
    LfcState lfcState,
    Map<String, double> dispatchedMap,
    ThemeData theme,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. System Summary Metric Ribbon
        _buildMetricRibbon(emsState, theme, isDark),

        const SizedBox(height: 16),

        // 2. Area Control Error (ACE) Gauge Card
        _buildAceGaugeCard(emsState, emsNotifier, lfcState, theme, isDark),

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

  /// Area Control Error (ACE) Gauge with color-coded threshold zones and interactive controls
  Widget _buildAceGaugeCard(
    EmsConsoleState state,
    EmsConsoleNotifier emsNotifier,
    LfcState lfcState,
    ThemeData theme,
    bool isDark,
  ) {
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
                    lfcState.enableAGC
                        ? 'AGC BALANCED'
                        : state.aceSeverity.title.toUpperCase(),
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

            // Visual Gauge Bar (scaled across -100 to +100 MW)
            _buildAceVisualBar(state.aceMW, isDark),

            const SizedBox(height: 8),

            // Gauge scale legend (-100 MW ... 0 ... +100 MW)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('-100 MW', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                Text('-20 MW [WARN]', style: TextStyle(fontSize: 10, color: Colors.amber.shade700)),
                Text('-5 MW', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                const Text('0 MW (BALANCED)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                Text('+5 MW', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                Text('+20 MW [WARN]', style: TextStyle(fontSize: 10, color: Colors.amber.shade700)),
                Text('+100 MW', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),

            const Divider(height: 24),

            // Interactive Controls: Secondary AGC Switch
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        lfcState.enableAGC ? Icons.check_circle : Icons.power_settings_new,
                        size: 20,
                        color: lfcState.enableAGC ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Secondary AGC Automatic Regulation',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              lfcState.enableAGC
                                  ? 'AGC integral control actively eliminates ACE (Δf → 0, ACE → 0 MW)'
                                  : 'Primary Droop Only: uncompensated frequency error and non-zero ACE',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: lfcState.enableAGC,
                  activeThumbColor: Colors.green,
                  onChanged: (val) => emsNotifier.toggleAgc(val),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Disturbance Slider
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Grid Active Load Surge (ΔP_L): ${lfcState.deltaPL1_MW.toStringAsFixed(0)} MW',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Text(
                  lfcState.enableAGC
                      ? 'Compensated by AGC'
                      : 'ACE = -ΔP_L = -${lfcState.deltaPL1_MW.toStringAsFixed(0)} MW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: lfcState.enableAGC ? Colors.green : severityColor,
                  ),
                ),
              ],
            ),
            Slider(
              value: lfcState.deltaPL1_MW.clamp(0.0, 150.0),
              min: 0.0,
              max: 150.0,
              divisions: 30,
              label: '${lfcState.deltaPL1_MW.toStringAsFixed(0)} MW',
              onChanged: (val) => emsNotifier.setLoadDisturbance(val),
            ),

            // Quick Scenario Chips
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _scenarioChip('0 MW (Balanced)', 0.0, lfcState.deltaPL1_MW, emsNotifier),
                _scenarioChip('15 MW (Advisory)', 15.0, lfcState.deltaPL1_MW, emsNotifier),
                _scenarioChip('50 MW (Emergency)', 50.0, lfcState.deltaPL1_MW, emsNotifier),
                _scenarioChip('90 MW (Benchmark)', 90.0, lfcState.deltaPL1_MW, emsNotifier),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _scenarioChip(
    String label,
    double mw,
    double currentMw,
    EmsConsoleNotifier notifier,
  ) {
    final isSelected = (currentMw - mw).abs() < 1e-2;
    return ActionChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      backgroundColor: isSelected ? Colors.blue.withValues(alpha: 0.2) : null,
      onPressed: () => notifier.setLoadDisturbance(mw),
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
    // Range is -100 MW to +100 MW (normalized 0.0 to 1.0)
    const minVal = -100.0;
    const maxVal = 100.0;
    final normalized = ((aceMW - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final pinPos = (normalized * totalWidth).clamp(6.0, totalWidth - 6.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Colored zone background bar (200 MW total flex)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 16,
                child: Row(
                  children: [
                    // Emergency left (-100 to -20 MW) -> 80/200
                    Expanded(flex: 80, child: Container(color: Colors.red.shade400)),
                    // Warning left (-20 to -5 MW) -> 15/200
                    Expanded(flex: 15, child: Container(color: Colors.amber.shade400)),
                    // Normal center (-5 to +5 MW) -> 10/200
                    Expanded(flex: 10, child: Container(color: Colors.green.shade500)),
                    // Warning right (+5 to +20 MW) -> 15/200
                    Expanded(flex: 15, child: Container(color: Colors.amber.shade400)),
                    // Emergency right (+20 to +100 MW) -> 80/200
                    Expanded(flex: 80, child: Container(color: Colors.red.shade400)),
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

  // ---------------------------------------------------------------------------
  // Tab 2: Examination Step-by-Step Hand Calculation Walkthrough for EMS
  // ---------------------------------------------------------------------------
  Widget _buildEmsExamStepByStep(
    BuildContext context,
    EmsConsoleState emsState,
    LfcState lfcState,
    EconomicDispatchState edState,
    ThemeData theme,
    bool isDark,
  ) {
    final area1 = lfcState.area1;
    final f0 = area1.nominalFreq;
    final bSys = area1.effectiveB;
    final sBase = area1.systemMvaBase;
    final deltaPL_MW = lfcState.deltaPL1_MW;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Exam Scenario Banner
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school, color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EE4530 Examination Working: EMS & SCADA Operations',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Analytical steps for Area Control Error (ACE), AGC dispatch, and real-time power balance',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Grid Base: S_base = ${sBase.toStringAsFixed(0)} MVA   ·   Frequency: f_0 = ${f0.toStringAsFixed(0)} Hz   ·   Area Bias: B = ${bSys.toStringAsFixed(2)} pu/pu',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // STEP 1: Area Control Error (ACE) Formulation
        _buildEmsStepCard(
          stepNumber: 1,
          title: 'Area Control Error (ACE) Formulation & Frequency Bias Setting',
          objective: 'Define the net interchange error and determine the frequency bias factor B.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _emsFormulaBox(
                r'ACE = \Delta P_{tie} + B \cdot \Delta f \quad (\text{MW})',
              ),
              const SizedBox(height: 10),
              const Text(
                '• Physical Meaning: ACE represents the instantaneous MW shortfall or surplus in the control area that must be adjusted by secondary control to maintain tie-line schedules and nominal grid frequency.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Frequency Bias Setting (B): B is chosen to match the natural area frequency response characteristic (B = β = D + Σ(1/R)). This ensures that for external disturbances in neighboring areas, the local ACE remains zero, preventing counter-productive secondary regulation.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Tie-Line Interchange Error:  ΔP_tie = ${emsState.deltaPtieMW.toStringAsFixed(2)} MW', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('• Frequency Bias Contribution:  B · Δf = ${emsState.freqBiasMW.toStringAsFixed(2)} MW (Δf = ${emsState.deltaFreqHz.toStringAsFixed(4)} Hz)', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    const Divider(height: 14),
                    Text(
                      'ACE = ${emsState.deltaPtieMW.toStringAsFixed(2)} + (${emsState.freqBiasMW.toStringAsFixed(2)}) = ${emsState.aceMW.toStringAsFixed(2)} MW',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace', color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 2: Regulation Deadbands & Severity Classification
        _buildEmsStepCard(
          stepNumber: 2,
          title: 'ACE Operational Severity Deadbands Classification',
          objective: 'Classify the severity of the Area Control Error according to control room operational standards.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Normal Operations: |ACE| ≤ 5.0 MW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green)),
                    Text('   System within regulation deadband; normal governor action suffices.', style: TextStyle(fontSize: 11)),
                    SizedBox(height: 6),
                    Text('2. Advisory / Warning: 5.0 MW < |ACE| ≤ 20.0 MW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.orange)),
                    Text('   Area control error exceeds deadband; AGC secondary dispatch is triggered.', style: TextStyle(fontSize: 11)),
                    SizedBox(height: 6),
                    Text('3. Emergency Alert: |ACE| > 20.0 MW', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.redAccent)),
                    Text('   Urgent spinning reserve dispatch required to avoid under-frequency load shedding.', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Current Operating Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (lfcState.enableAGC || emsState.aceSeverity == AceSeverity.normal)
                          ? Colors.green.withValues(alpha: 0.15)
                          : (emsState.aceSeverity == AceSeverity.warning
                              ? Colors.orange.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lfcState.enableAGC
                          ? 'NORMAL OPERATIONS (AGC REGULATING)'
                          : emsState.aceSeverity.title.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: (lfcState.enableAGC || emsState.aceSeverity == AceSeverity.normal)
                            ? Colors.green
                            : (emsState.aceSeverity == AceSeverity.warning ? Colors.orange : Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 3: Secondary AGC Command Allocation
        _buildEmsStepCard(
          stepNumber: 3,
          title: 'Secondary AGC Integral Control & Generator Command Allocation',
          objective: 'Formulate the secondary integral regulation loop and unit command distribution.',
          theme: theme,
          isDark: isDark,
          isHighlighted: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _emsFormulaBox(
                r'\Delta P_{ref}(t) = -K_I \int_0^t ACE(\tau) \, d\tau \quad \text{and} \quad \Delta P_{ref,i} = \alpha_i \cdot \Delta P_{ref}',
              ),
              const SizedBox(height: 10),
              const Text(
                '• Exam Distinction (Primary vs Secondary):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                '  - Primary Droop: Proportional control only. Leaves a permanent steady-state frequency error: Δf_ss = -ΔP_L / β_sys.',
                style: TextStyle(fontSize: 12),
              ),
              const Text(
                '  - Secondary AGC: Integral control law. Continues adjusting reference power ΔP_ref until the integral of ACE reaches zero, ensuring lim_{t→∞} Δf(t) = 0 and lim_{t→∞} ACE(t) = 0.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• Integral Gain: K_I = ${area1.integralGainKi.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Uncompensated Load Surge: ΔP_L = ${deltaPL_MW.toStringAsFixed(1)} MW',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      lfcState.enableAGC
                          ? '• Current AGC State: ACTIVE → Secondary integral action has compensated generation to drive ACE to 0.00 MW and f to 50.000 Hz.'
                          : '• Current AGC State: INACTIVE → Uncompensated primary droop leaves steady-state error Δf = ${emsState.deltaFreqHz.toStringAsFixed(4)} Hz and ACE = ${emsState.aceMW.toStringAsFixed(2)} MW.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: lfcState.enableAGC ? Colors.green : Colors.deepOrangeAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 4: Real-Time Energy Balance & System Marginal Cost
        _buildEmsStepCard(
          stepNumber: 4,
          title: 'Transmission Energy Balance & System Marginal Clearing Cost (λ)',
          objective: 'Balance total grid generation, load demand, and transmission losses.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _emsFormulaBox(
                r'\sum_{i=1}^{N_g} P_{Gi} = \sum_{j=1}^{N_l} P_{Lj} + P_{losses} \quad \text{and} \quad \lambda = \text{ICR}_i(P_i)',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Grid Generation (Σ P_G):', style: TextStyle(fontSize: 12)),
                        Text('${emsState.totalGenMW.toStringAsFixed(2)} MW + j${emsState.totalGenMvar.toStringAsFixed(2)} MVAR', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Load Demand (Σ P_L):', style: TextStyle(fontSize: 12)),
                        Text('${emsState.totalLoadMW.toStringAsFixed(2)} MW + j${emsState.totalLoadMvar.toStringAsFixed(2)} MVAR', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Transmission Losses (P_loss):', style: TextStyle(fontSize: 12)),
                        Text('${emsState.totalLossMW.toStringAsFixed(2)} MW + j${emsState.totalLossMvar.toStringAsFixed(2)} MVAR', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12, color: Colors.redAccent)),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('System Marginal Cost (λ):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          '${emsState.systemLambda.toStringAsFixed(4)} \$/MWh',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace', color: Colors.blueAccent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEmsStepCard({
    required int stepNumber,
    required String title,
    required String objective,
    required Widget content,
    required ThemeData theme,
    required bool isDark,
    bool isHighlighted = false,
  }) {
    return Card(
      elevation: isHighlighted ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isHighlighted
            ? const BorderSide(color: Colors.blueAccent, width: 1.5)
            : BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: isHighlighted ? Colors.blueAccent : theme.colorScheme.primary,
                  child: Text(
                    stepNumber.toString(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isHighlighted ? Colors.blueAccent : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              objective,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            const Divider(height: 20),
            content,
          ],
        ),
      ),
    );
  }

  Widget _emsFormulaBox(String tex) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3A66).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF0F3A66).withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Math.tex(
          tex,
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
