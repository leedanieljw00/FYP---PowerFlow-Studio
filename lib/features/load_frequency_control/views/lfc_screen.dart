import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/load_frequency_control/two_area_lfc.dart';
import '../providers/lfc_provider.dart';

class LfcScreen extends ConsumerStatefulWidget {
  const LfcScreen({super.key});

  @override
  ConsumerState<LfcScreen> createState() => _LfcScreenState();
}

class _LfcScreenState extends ConsumerState<LfcScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lfcProvider);
    final notifier = ref.read(lfcProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Load Frequency Control (LFC)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Droop, Tie-Line & AGC Secondary Control · EE4530', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'ACE Inverse Calculator (Assignment 1 Q1)',
            onPressed: () => _showAceCalculatorDialog(context),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Load Presets',
            onSelected: (val) {
              if (val == 'droop') {
                notifier.loadParallelDroopPreset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded EE4530 Example 2.3 Dual-Unit Droop Benchmark')),
                );
              } else if (val == 'twoarea') {
                notifier.loadAssignment1TwoAreaPreset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded EE4530 Assignment 1 Q1 Two-Area Interconnection')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'droop',
                child: Text('EE4530 Ex 2.3: Parallel Droop Sharing (R1=6%, R2=4%)'),
              ),
              PopupMenuItem(
                value: 'twoarea',
                child: Text('EE4530 Assignment 1 Q1: Two-Area Interconnected Grid'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.settings_input_component), text: 'Area Config'),
            Tab(icon: Icon(Icons.show_chart), text: 'Transient Dynamic Δf(t)'),
            Tab(icon: Icon(Icons.hub_outlined), text: 'Interconnection & ACE'),
            Tab(icon: Icon(Icons.school_outlined), text: 'Exam Step-by-Step'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConfigTab(context, state, notifier, theme, isDark),
          _buildTransientTab(context, state, theme, isDark),
          _buildInterconnectionTab(context, state, theme, isDark),
          _buildExamStepByStepTab(context, state, theme, isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Configuration & Steady-State Results
  // ---------------------------------------------------------------------------
  Widget _buildConfigTab(
    BuildContext context,
    LfcState state,
    LfcNotifier notifier,
    ThemeData theme,
    bool isDark,
  ) {
    final singleR = state.singleAreaResult;
    final twoR = state.twoAreaResult;

    final deltaF_Hz = singleR?.deltaF_Hz ?? twoR?.deltaF_Hz ?? 0.0;
    final deltaF_pu = singleR?.deltaF_pu ?? twoR?.deltaF_pu ?? 0.0;
    final fFinal = singleR?.fFinal_Hz ?? twoR?.fFinal_Hz ?? 50.0;
    final beta = singleR?.betaSys ?? twoR?.beta1 ?? 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Mode Selector Bar
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('System Operation Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.primary)),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Single Area (Droop)')),
                        ButtonSegment(value: true, label: Text('Two-Area Interconnected')),
                      ],
                      selected: {state.isTwoAreaMode},
                      onSelectionChanged: (set) => notifier.setTwoAreaMode(set.first),
                    ),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Area 1 Load Surge (ΔP_L1): ${state.deltaPL1_MW.toStringAsFixed(0)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Slider(
                            value: state.deltaPL1_MW.clamp(0.0, 500.0),
                            min: 0.0,
                            max: 500.0,
                            divisions: 50,
                            label: '${state.deltaPL1_MW.toStringAsFixed(0)} MW',
                            onChanged: (val) => notifier.setLoadSurgeArea1(val),
                          ),
                        ],
                      ),
                    ),
                    if (state.isTwoAreaMode) ...[
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Area 2 Load Surge (ΔP_L2): ${state.deltaPL2_MW.toStringAsFixed(0)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Slider(
                              value: state.deltaPL2_MW.clamp(0.0, 500.0),
                              min: 0.0,
                              max: 500.0,
                              divisions: 50,
                              label: '${state.deltaPL2_MW.toStringAsFixed(0)} MW',
                              onChanged: (val) => notifier.setLoadSurgeArea2(val),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Secondary AGC Integral Control (K_I)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: const Text('Integrates frequency/ACE to eliminate steady-state error (Δf → 0)', style: TextStyle(fontSize: 11)),
                  value: state.enableAGC,
                  onChanged: (val) => notifier.setEnableAGC(val),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Steady State Metrics Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: isDark ? Colors.grey.shade900 : const Color(0xFFF0FDF4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, color: deltaF_Hz.abs() > 0.5 ? Colors.orange : Colors.green, size: 22),
                    const SizedBox(width: 8),
                    const Text('Steady-State Frequency Response', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        'Frequency Deviation Δf',
                        '${deltaF_Hz >= 0 ? "+" : ""}${deltaF_Hz.toStringAsFixed(4)} Hz',
                        '${deltaF_pu.toStringAsFixed(6)} pu',
                        Colors.teal,
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        'Final Steady Frequency',
                        '${fFinal.toStringAsFixed(4)} Hz',
                        'Nominal: ${state.area1.nominalFreq.toStringAsFixed(0)} Hz',
                        Colors.indigo,
                      ),
                    ),
                    Expanded(
                      child: _buildMetricTile(
                        'Frequency Response β_sys',
                        '${beta.toStringAsFixed(2)} pu/pu',
                        'D + Σ(1/R)',
                        Colors.purple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Parallel Generator Sharing (Single Area)
        if (singleR != null) ...[
          Text('Governor Power Sharing (ΔP_m)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary)),
          const SizedBox(height: 8),
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  for (final g in singleR.generatorResponses)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.power, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(g.generatorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ),
                          Text(
                            '+${g.deltaP_MW.toStringAsFixed(2)} MW',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace', color: Colors.blueAccent),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.blue.withAlpha(20), borderRadius: BorderRadius.circular(4)),
                            child: Text('${(g.participationFactor * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Load Damping Relief (D·Δf):', style: TextStyle(fontSize: 13)),
                      Text('${singleR.dampingRelief_MW.toStringAsFixed(2)} MW', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Power Balance Check:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      Text(
                        '${(singleR.totalGovernorPower_MW + singleR.dampingRelief_MW).toStringAsFixed(2)} MW = ${singleR.deltaPL_MW.toStringAsFixed(2)} MW',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildMetricTile(String title, String val1, String val2, Color accent) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
          Text(val2, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Dynamic Transient Response Plot (fl_chart)
  // ---------------------------------------------------------------------------
  Widget _buildTransientTab(
    BuildContext context,
    LfcState state,
    ThemeData theme,
    bool isDark,
  ) {
    final traj = state.transientTrajectory;

    if (traj.isEmpty) {
      return const Center(child: Text('No transient simulation data available.'));
    }

    final freqSpots = <FlSpot>[];
    final pSpots = <FlSpot>[];
    double minF = 50.0;
    double maxF = 50.0;

    for (final p in traj) {
      freqSpots.add(FlSpot(p.time, p.frequency_Hz));
      pSpots.add(FlSpot(p.time, p.deltaPm_pu * 1000.0)); // In MW on 1000 MVA base
      if (p.frequency_Hz < minF) minF = p.frequency_Hz;
      if (p.frequency_Hz > maxF) maxF = p.frequency_Hz;
    }

    final fFinal = state.singleAreaResult?.fFinal_Hz ?? 50.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transient Frequency Trajectory f(t)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
                    ),
                    Text(
                      state.enableAGC ? 'Secondary AGC Active' : 'Primary Droop Only',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: state.enableAGC ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Closed-loop governor/turbine ODE dynamic step response to ΔP_L = ${state.deltaPL1_MW.toStringAsFixed(0)} MW disturbance.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 320,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: 20,
                      minY: (minF - 0.05).clamp(48.0, 50.0),
                      maxY: (maxF + 0.05).clamp(50.0, 52.0),
                      lineBarsData: [
                        LineChartBarData(
                          spots: freqSpots,
                          isCurved: true,
                          curveSmoothness: 0.2,
                          color: state.enableAGC ? Colors.greenAccent.shade700 : Colors.blueAccent,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: 50.0,
                            color: Colors.grey,
                            strokeWidth: 1,
                            dashArray: [4, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              labelResolver: (_) => ' 50.0 Hz (Nominal)',
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          ),
                          if (!state.enableAGC)
                            HorizontalLine(
                              y: fFinal,
                              color: Colors.redAccent,
                              strokeWidth: 1.5,
                              dashArray: [5, 5],
                              label: HorizontalLineLabel(
                                show: true,
                                alignment: Alignment.bottomRight,
                                labelResolver: (_) => ' f_ss = ${fFinal.toStringAsFixed(3)} Hz',
                                style: const TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          axisNameWidget: const Text('Time t (seconds)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: 2),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: const Text('Grid Frequency (Hz)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          sideTitles: SideTitles(showTitles: true, reservedSize: 42, interval: 0.05),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        getDrawingHorizontalLine: (_) => FlLine(color: isDark ? Colors.white12 : Colors.black12, strokeWidth: 1),
                        getDrawingVerticalLine: (_) => FlLine(color: isDark ? Colors.white12 : Colors.black12, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 20, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.enableAGC
                              ? 'Secondary AGC integral control active: integral action successfully eliminates the frequency error, returning frequency back to nominal 50.00 Hz.'
                              : 'Primary droop control only: note the frequency nadir followed by steady-state offset Δf_ss = ${(fFinal - 50.0).toStringAsFixed(4)} Hz.',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Two-Area Interconnection & ACE
  // ---------------------------------------------------------------------------
  Widget _buildInterconnectionTab(
    BuildContext context,
    LfcState state,
    ThemeData theme,
    bool isDark,
  ) {
    final twoR = state.twoAreaResult;

    if (!state.isTwoAreaMode || twoR == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hub_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Switch to "Two-Area Interconnected" mode to inspect tie-line flow and ACE.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                ref.read(lfcProvider.notifier).loadAssignment1TwoAreaPreset();
              },
              child: const Text('Load Assignment 1 Q1 Two-Area Network'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Two-Area Power Exchange & Area Control Error (ACE)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tie-line interchange: ΔP_tie1 = (ΔP_L2·β1 - ΔP_L1·β2) / (β1 + β2)   ·   ACE = ΔP_tie + B·Δf',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.withAlpha(80)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Area 1 ACE (ACE_1)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                            const SizedBox(height: 4),
                            Text('${twoR.ace1_MW.toStringAsFixed(2)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace')),
                            Text('Bias B_1 = ${twoR.b1.toStringAsFixed(1)} pu/pu', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.teal.withAlpha(80)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Area 2 ACE (ACE_2)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                            const SizedBox(height: 4),
                            Text('${twoR.ace2_MW.toStringAsFixed(2)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace')),
                            Text('Bias B_2 = ${twoR.b2.toStringAsFixed(1)} pu/pu', style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_alt, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Tie-Line Power Flow Deviation (Area 1 → Area 2)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text(
                              'ΔP_tie,12 = ${twoR.deltaPtie1_MW.toStringAsFixed(2)} MW (${twoR.deltaPtie1_pu.toStringAsFixed(4)} pu)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace', color: Colors.deepOrange),
                            ),
                            Text(
                              twoR.deltaPtie1_MW < 0
                                  ? 'Area 2 is exporting ${twoR.deltaPtie1_MW.abs().toStringAsFixed(2)} MW into Area 1 to support the deficit.'
                                  : 'Area 1 is exporting ${twoR.deltaPtie1_MW.toStringAsFixed(2)} MW into Area 2.',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ACE Inverse Calculator Dialog (Assignment 1 Q1)
  // ---------------------------------------------------------------------------
  void _showAceCalculatorDialog(BuildContext context) {
    double ace1 = -0.25;
    double ace2 = 0.10;
    double b1 = 12.5;
    double b2 = 25.0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final solution = TwoAreaLfcSolver.solveFromAces(ace1: ace1, ace2: ace2, b1: b1, b2: b2);

            return AlertDialog(
              title: const Text('ACE Inverse Solver (Assignment 1 Q1)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Computes frequency deviation Δf and tie-line flow ΔP_tie directly from measured Area Control Errors:',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: ace1.toString(),
                      decoration: const InputDecoration(labelText: 'ACE 1 (pu)', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onChanged: (v) => setState(() => ace1 = double.tryParse(v) ?? ace1),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: ace2.toString(),
                      decoration: const InputDecoration(labelText: 'ACE 2 (pu)', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      onChanged: (v) => setState(() => ace2 = double.tryParse(v) ?? ace2),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: b1.toString(),
                      decoration: const InputDecoration(labelText: 'Frequency Bias B_1 (pu/pu)', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => setState(() => b1 = double.tryParse(v) ?? b1),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      initialValue: b2.toString(),
                      decoration: const InputDecoration(labelText: 'Frequency Bias B_2 (pu/pu)', isDense: true),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => setState(() => b2 = double.tryParse(v) ?? b2),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.withAlpha(20), borderRadius: BorderRadius.circular(8)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Solved Deviations:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('Δf = (ACE1 + ACE2) / (B1 + B2) = ${solution.deltaF_pu.toStringAsFixed(6)} pu', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                          Text('At 50 Hz: Δf = ${(solution.deltaF_pu * 50.0).toStringAsFixed(4)} Hz', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                          const SizedBox(height: 4),
                          Text('ΔP_tie1 = (B2·ACE1 - B1·ACE2) / (B1 + B2) = ${solution.deltaPtie1_pu.toStringAsFixed(6)} pu', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Examination Step-by-Step Hand Calculation Walkthrough
  // ---------------------------------------------------------------------------
  Widget _buildExamStepByStepTab(
    BuildContext context,
    LfcState state,
    ThemeData theme,
    bool isDark,
  ) {
    final area1 = state.area1;
    final sBase = area1.systemMvaBase;
    final f0 = area1.nominalFreq;
    final deltaPL_MW = state.deltaPL1_MW;
    final deltaPL_pu = deltaPL_MW / sBase;
    final isTwoArea = state.isTwoAreaMode;

    // Single Area Calculations
    final singleResult = state.singleAreaResult;
    final betaSys = singleResult?.betaSys ?? area1.betaSys;
    final deltaF_pu = betaSys > 0 ? -deltaPL_pu / betaSys : 0.0;
    final deltaF_Hz = deltaF_pu * f0;
    final fFinal = f0 + deltaF_Hz;

    // Two Area Calculations
    final twoResult = state.twoAreaResult;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Exam Scenario Banner
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF0FDF4),
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
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.school, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'EE4530 Examination Working: Load Frequency Control',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Comprehensive step-by-step hand calculation procedures for governor droop & ACE',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        isTwoArea ? 'TWO-AREA INTERCONNECTED' : 'SINGLE-AREA DROOP',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: isTwoArea
                          ? Colors.purple.withValues(alpha: 0.15)
                          : Colors.teal.withValues(alpha: 0.15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Disturbance: ΔP_L1 = ${deltaPL_MW.toStringAsFixed(1)} MW   ·   System Base: S_base = ${sBase.toStringAsFixed(0)} MVA   ·   Nominal: f_0 = ${f0.toStringAsFixed(0)} Hz',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // SECTION A: Multi-Generator Droop Sharing
        _buildSectionHeader('Part A: Parallel Governor Droop Sharing (EE4530 Ex 2.3 & Tut 4 Q1)'),
        const SizedBox(height: 10),

        // STEP 1: Convert Droops to System Base
        _buildLfcStepCard(
          stepNumber: 1,
          title: 'Convert Speed Droop Regulation Constants to Common System Base',
          objective: 'Ensure all governor droops R_i are on the common system MVA base (S_base = ${sBase.toStringAsFixed(0)} MVA).',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'R_{i,sys} = R_{i,given} \times \left( \frac{S_{base}}{S_{ni}} \right)',
              ),
              const SizedBox(height: 10),
              ...area1.generators.asMap().entries.map((entry) {
                final i = entry.key;
                final g = entry.value;
                final rSys = g.droopOnSystemBase(sBase);
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text('${g.name}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Expanded(
                        child: Text(
                          'R_{${i + 1},sys} = ${(g.droopR * 100).toStringAsFixed(1)}% × (${sBase.toStringAsFixed(0)} / ${g.mvaBase.toStringAsFixed(0)}) = ${rSys.toStringAsFixed(4)} pu',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.blueAccent),
                        ),
                      ),
                      Text(
                        '1/R = ${(1.0 / rSys).toStringAsFixed(2)} pu/pu',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 2: Compute Area Frequency Response Characteristic beta_sys
        _buildLfcStepCard(
          stepNumber: 2,
          title: 'Calculate System Frequency Response Characteristic (β_sys)',
          objective: 'Sum the load damping constant D and all governor stiffnesses (1/R_i).',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'\beta_{sys} = D + \sum_{i=1}^{N_g} \frac{1}{R_{i,sys}} \quad (\text{pu/pu or MW/Hz})',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Load damping constant: D = ${area1.dampingD.toStringAsFixed(2)} pu/pu', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    ...area1.generators.asMap().entries.map((entry) {
                      final i = entry.key;
                      final g = entry.value;
                      final rSys = g.droopOnSystemBase(sBase);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text('• 1 / R_{${i + 1},sys} = 1 / ${rSys.toStringAsFixed(4)} = ${(1.0 / rSys).toStringAsFixed(4)} pu/pu', style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                      );
                    }),
                    const Divider(height: 14),
                    Text(
                      'β_sys = ${area1.dampingD.toStringAsFixed(2)} + ${area1.generators.map((g) => (1.0 / g.droopOnSystemBase(sBase)).toStringAsFixed(2)).join(" + ")} = ${betaSys.toStringAsFixed(4)} pu/pu',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace', color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 3: Compute Steady-State Frequency Deviation
        _buildLfcStepCard(
          stepNumber: 3,
          title: 'Calculate Steady-State Frequency Deviation (Δf)',
          objective: 'Apply the static droop governing equation Δf = -ΔP_L / β_sys.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'\Delta f_{pu} = -\frac{\Delta P_{L,pu}}{\beta_{sys}} \implies \Delta f_{\text{Hz}} = \Delta f_{pu} \times f_0',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '• Step load surge in per-unit:  ΔP_L,pu = ${deltaPL_MW.toStringAsFixed(1)} MW / ${sBase.toStringAsFixed(0)} MVA = ${deltaPL_pu.toStringAsFixed(5)} pu',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Frequency deviation in pu:  Δf_pu = -(${deltaPL_pu.toStringAsFixed(5)}) / ${betaSys.toStringAsFixed(4)} = ${deltaF_pu.toStringAsFixed(6)} pu',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Frequency deviation in Hertz:  Δf_Hz = ${deltaF_pu.toStringAsFixed(6)} × ${f0.toStringAsFixed(0)} = ${deltaF_Hz.toStringAsFixed(4)} Hz',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Final settled grid frequency:  f_final = ${f0.toStringAsFixed(1)} + (${deltaF_Hz.toStringAsFixed(4)}) = ${fFinal.toStringAsFixed(4)} Hz',
                      style: const TextStyle(fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.blueAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 4: Individual Unit Pickups and Participation Factors
        _buildLfcStepCard(
          stepNumber: 4,
          title: 'Calculate Generator Power Pickups & Participation Factors',
          objective: 'Evaluate individual turbine MW response: ΔP_mi = -Δf / R_i.',
          theme: theme,
          isDark: isDark,
          isHighlighted: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'\Delta P_{mi,pu} = -\frac{\Delta f_{pu}}{R_{i,sys}} \quad \text{and} \quad \Delta P_{mi,\text{MW}} = \Delta P_{mi,pu} \times S_{base}',
              ),
              const SizedBox(height: 10),
              if (singleResult != null) ...[
                for (final g in singleResult.generatorResponses) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(g.generatorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '+${g.deltaP_MW.toStringAsFixed(2)} MW (${g.deltaP_pu.toStringAsFixed(5)} pu)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', color: Colors.blueAccent, fontSize: 13),
                            ),
                            Text(
                              'Participation Factor: ${(g.participationFactor * 100).toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• Load Damping Relief: ΔP_D = D · (-Δf) = ${(singleResult.dampingRelief_MW).toStringAsFixed(2)} MW',
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Power Balance Verification:  Σ ΔP_m (${singleResult.totalGovernorPower_MW.toStringAsFixed(2)}) + ΔP_D (${singleResult.dampingRelief_MW.toStringAsFixed(2)}) = ${deltaPL_MW.toStringAsFixed(2)} MW  ✓',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 24),

        // SECTION B: Two-Area Interconnected Grid & ACE
        _buildSectionHeader('Part B: Two-Area Interconnection & Area Control Error (ACE)'),
        const SizedBox(height: 10),

        _buildLfcStepCard(
          stepNumber: 5,
          title: 'Two-Area Tie-Line Power Flow Deviation & Frequency Formulation',
          objective: 'Model tie-line active power exchange under load surges in Area 1 and Area 2.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'\Delta P_{tie1} = \frac{\beta_2 \Delta P_{L1} - \beta_1 \Delta P_{L2}}{\beta_1 + \beta_2} \quad \text{and} \quad \Delta f = -\frac{\Delta P_{L1} + \Delta P_{L2}}{\beta_1 + \beta_2}',
              ),
              const SizedBox(height: 10),
              if (twoResult != null) ...[
                Text('• Area 1 Bias B_1 = β_1 = ${twoResult.b1.toStringAsFixed(2)} pu/pu', style: const TextStyle(fontSize: 12)),
                Text('• Area 2 Bias B_2 = β_2 = ${twoResult.b2.toStringAsFixed(2)} pu/pu', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text('• Solved Tie-Line Flow Deviation: ΔP_tie1 = ${twoResult.deltaPtie1_MW.toStringAsFixed(2)} MW (${twoResult.deltaPtie1_pu.toStringAsFixed(4)} pu)', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13, color: Colors.deepOrange)),
                Text('• Area Control Error ACE_1 = ΔP_tie1 + B_1·Δf = ${twoResult.ace1_MW.toStringAsFixed(2)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13, color: Colors.indigo)),
                Text('• Area Control Error ACE_2 = -ΔP_tie1 + B_2·Δf = ${twoResult.ace2_MW.toStringAsFixed(2)} MW', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13, color: Colors.teal)),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // SECTION C: Assignment 1 Question 1 Worked Walkthrough
        _buildSectionHeader('Part C: EE4530 Assignment 1 Question 1 Worked Solution'),
        const SizedBox(height: 10),

        _buildLfcStepCard(
          stepNumber: 6,
          title: 'ACE Inverse Solver (Deriving Δf and ΔP_tie from measured ACE1 & ACE2)',
          objective: 'Given ACE1 = -0.25 pu, ACE2 = 0.10 pu, B1 = 12.5 pu, B2 = 25.0 pu, solve for Δf and ΔP_tie1.',
          theme: theme,
          isDark: isDark,
          isHighlighted: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _lfcFormulaBox(
                r'\Delta f = \frac{ACE_1 + ACE_2}{B_1 + B_2} \quad \text{and} \quad \Delta P_{tie1} = \frac{B_2 \cdot ACE_1 - B_1 \cdot ACE_2}{B_1 + B_2}',
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Adding equations:  ACE_1 + ACE_2 = (ΔP_tie1 - ΔP_tie1) + (B_1 + B_2)Δf = (B_1 + B_2)Δf', style: TextStyle(fontSize: 12)),
                    SizedBox(height: 4),
                    Text('   Δf = (-0.25 + 0.10) / (12.5 + 25.0) = -0.15 / 37.5 = -0.0040 pu', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent)),
                    Text('   At 50 Hz: Δf = -0.0040 × 50.0 = -0.2000 Hz', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueAccent)),
                    Divider(height: 16),
                    Text('2. Cross-multiplying:  B_2·ACE_1 - B_1·ACE_2 = (B_1 + B_2)ΔP_tie1', style: TextStyle(fontSize: 12)),
                    SizedBox(height: 4),
                    Text('   ΔP_tie1 = [25.0(-0.25) - 12.5(0.10)] / 37.5 = (-6.25 - 1.25) / 37.5 = -7.50 / 37.5 = -0.2000 pu', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange)),
                    Divider(height: 16),
                    Text('3. Verification Check:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Text('   ACE_1 = -0.2000 + 12.5(-0.0040) = -0.2000 - 0.0500 = -0.2500 pu  ✓', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.green)),
                    Text('   ACE_2 = -(-0.2000) + 25.0(-0.0040) = +0.2000 - 0.1000 = +0.1000 pu  ✓', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.green)),
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

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueAccent),
    );
  }

  Widget _buildLfcStepCard({
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

  Widget _lfcFormulaBox(String tex) {
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
