import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/economic_dispatch/generator_model.dart';
import '../providers/economic_dispatch_provider.dart';

class EconomicDispatchScreen extends ConsumerStatefulWidget {
  const EconomicDispatchScreen({super.key});

  @override
  ConsumerState<EconomicDispatchScreen> createState() => _EconomicDispatchScreenState();
}

class _EconomicDispatchScreenState extends ConsumerState<EconomicDispatchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Color> _unitColors = [
    Colors.blueAccent,
    Colors.deepOrangeAccent,
    Colors.teal,
    Colors.purpleAccent,
    Colors.amber,
  ];

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
    final state = ref.watch(economicDispatchProvider);
    final notifier = ref.read(economicDispatchProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Economic Dispatch (ED)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Optimal Generation Allocation · EE4530', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Load Presets',
            onSelected: (val) {
              if (val == 'ee4530') {
                notifier.loadEe4530Preset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded EE4530 Example 2.6 / Tutorial 5 Benchmark')),
                );
              } else if (val == '3unit') {
                notifier.load3UnitPreset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded 3-Unit System with B-Matrix')),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'ee4530',
                child: Text('EE4530 Tutorial 5 Q1 (2-Unit Classic)'),
              ),
              PopupMenuItem(
                value: '3unit',
                child: Text('3-Unit Thermal System with Losses'),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'Units & Demand'),
            Tab(icon: Icon(Icons.show_chart), text: 'Equal Slope (ICR)'),
            Tab(icon: Icon(Icons.history), text: 'Iteration Steps'),
            Tab(icon: Icon(Icons.school_outlined), text: 'Exam Step-by-Step'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConfigurationTab(context, state, notifier, theme, isDark),
          _buildChartTab(context, state, theme, isDark),
          _buildStepsTab(context, state, theme, isDark),
          _buildExamStepByStepTab(context, state, theme, isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 1: Units Configuration & Results
  // ---------------------------------------------------------------------------
  Widget _buildConfigurationTab(
    BuildContext context,
    EconomicDispatchState state,
    EconomicDispatchNotifier notifier,
    ThemeData theme,
    bool isDark,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Demand & Control Controls Card
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
                      'System Active Load Demand (P_D)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.primary),
                    ),
                    Text(
                      '${state.demand.toStringAsFixed(1)} MW',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                Slider(
                  value: state.demand.clamp(100.0, 3000.0),
                  min: 100.0,
                  max: 3000.0,
                  divisions: 290,
                  label: '${state.demand.toStringAsFixed(0)} MW',
                  onChanged: (val) => notifier.setDemand(val),
                ),
                const Divider(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enforce P_min / P_max', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text('Clamp violated units & re-dispatch', style: TextStyle(fontSize: 11)),
                        value: state.enforceLimits,
                        onChanged: state.includeLosses ? null : (val) => notifier.setEnforceLimits(val),
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include Grid Losses', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: const Text("Kron's B-matrix penalty factors", style: TextStyle(fontSize: 11)),
                        value: state.includeLosses,
                        onChanged: (val) => notifier.setIncludeLosses(val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Solution Summary Card
        _buildSolutionSummaryCard(context, state, isDark),
        const SizedBox(height: 16),

        // Generators List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Generating Units (${state.units.length})',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
            ),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Generator'),
              onPressed: () => notifier.addUnit(),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Generator Edit Cards
        for (var i = 0; i < state.units.length; i++)
          _buildGeneratorCard(context, i, state.units[i], state, notifier, isDark),

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSolutionSummaryCard(
    BuildContext context,
    EconomicDispatchState state,
    bool isDark,
  ) {
    final lr = state.losslessResult;
    final lossR = state.lossResult;

    if (lr == null && lossR == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(20),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.redAccent),
        ),
        child: Text(
          state.errorMessage ?? 'No valid dispatch solution available.',
          style: const TextStyle(color: Colors.redAccent, fontSize: 13),
        ),
      );
    }

    final lambda = lr?.lambda ?? lossR?.lambda ?? 0.0;
    final totalCost = lr?.totalCost ?? lossR?.totalCost ?? 0.0;
    final totalPower = lr?.totalPower ?? lossR?.totalPower ?? 0.0;
    final loss = lossR?.transmissionLoss ?? 0.0;
    final savings = lr?.savings ?? 0.0;
    final savingsPct = lr?.savingsPercent ?? 0.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey.shade900 : const Color(0xFFF0F7FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Text(
                  state.includeLosses ? 'Loss-Included Dispatch Solved' : 'Optimal Lossless Dispatch Solved',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'System Marginal Cost λ',
                    '${lambda.toStringAsFixed(4)} \$/MWh',
                    Colors.indigo,
                  ),
                ),
                Expanded(
                  child: _buildMetricTile(
                    'Total Fuel Cost',
                    '${totalCost.toStringAsFixed(2)} \$/h',
                    Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'Total Generation',
                    '${totalPower.toStringAsFixed(2)} MW',
                    Colors.teal,
                  ),
                ),
                Expanded(
                  child: state.includeLosses
                      ? _buildMetricTile(
                          'Transmission Loss (P_L)',
                          '${loss.toStringAsFixed(3)} MW',
                          Colors.purple,
                        )
                      : _buildMetricTile(
                          'Savings vs Equal Share',
                          '${savings.toStringAsFixed(2)} \$/h (${savingsPct.toStringAsFixed(1)}%)',
                          Colors.green,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, Color accent) {
    return Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: accent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildGeneratorCard(
    BuildContext context,
    int index,
    GeneratorUnit unit,
    EconomicDispatchState state,
    EconomicDispatchNotifier notifier,
    bool isDark,
  ) {
    final color = _unitColors[index % _unitColors.length];
    final dispatchedP = state.losslessResult?.powers[unit.id] ??
        state.lossResult?.powers[unit.id] ??
        0.0;
    final isClamped = state.losslessResult?.clampedUnits.containsKey(unit.id) ?? false;
    final pf = state.lossResult?.penaltyFactors[unit.id] ?? 1.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unit.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'P_G = ${dispatchedP.toStringAsFixed(2)} MW',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color, fontFamily: 'monospace'),
                  ),
                ),
                if (isClamped) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent),
                    ),
                    child: const Text('CLAMPED', style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ],
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  onPressed: () => notifier.removeUnit(index),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'C(P) = ${unit.alpha} + ${unit.beta}·P + ${unit.gamma}·P²   ·   ICR = ${unit.beta} + ${(2 * unit.gamma).toStringAsFixed(5)}·P',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, fontFamily: 'monospace'),
            ),
            if (state.includeLosses)
              Text(
                'Penalty factor L = ${pf.toStringAsFixed(4)}   ·   L·ICR = ${(pf * unit.icrAt(dispatchedP)).toStringAsFixed(4)} \$/MWh',
                style: const TextStyle(fontSize: 11, color: Colors.purpleAccent, fontFamily: 'monospace'),
              ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField('α (\$/h)', unit.alpha, (v) => notifier.updateUnit(index, unit.copyWith(alpha: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField('β (\$/MWh)', unit.beta, (v) => notifier.updateUnit(index, unit.copyWith(beta: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField('γ (\$/MW²h)', unit.gamma, (v) => notifier.updateUnit(index, unit.copyWith(gamma: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField('P_min (MW)', unit.pMin, (v) => notifier.updateUnit(index, unit.copyWith(pMin: v))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField('P_max (MW)', unit.pMax, (v) => notifier.updateUnit(index, unit.copyWith(pMax: v))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 2: Equal Slope ICR Curve Visualizer (fl_chart)
  // ---------------------------------------------------------------------------
  Widget _buildChartTab(
    BuildContext context,
    EconomicDispatchState state,
    ThemeData theme,
    bool isDark,
  ) {
    final lr = state.losslessResult;
    final lossR = state.lossResult;
    final lambda = lr?.lambda ?? lossR?.lambda ?? 10.0;

    // Build LineChartData
    final lineBarsData = <LineChartBarData>[];
    double maxP = 100.0;
    double maxIcr = 15.0;

    for (var i = 0; i < state.units.length; i++) {
      final u = state.units[i];
      final color = _unitColors[i % _unitColors.length];

      final spots = <FlSpot>[];
      final pMin = u.pMin;
      final pMax = u.pMax;
      if (pMax > maxP) maxP = pMax;

      for (var p = pMin; p <= pMax + 1e-6; p += (pMax - pMin) / 10.0) {
        final icr = u.icrAt(p);
        if (icr > maxIcr) maxIcr = icr;
        spots.add(FlSpot(p, icr));
      }

      lineBarsData.add(
        LineChartBarData(
          spots: spots,
          isCurved: false,
          color: color,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            checkToShowDot: (spot, barData) {
              return spot == spots.first || spot == spots.last;
            },
          ),
        ),
      );
    }

    if (lambda > maxIcr) maxIcr = lambda + 2.0;

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
                      'Equal Slope Criterion: ICR_i(P_i) = λ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
                    ),
                    Text(
                      'λ = ${lambda.toStringAsFixed(4)} \$/MWh',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigoAccent, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'The horizontal dashed line represents system incremental cost λ. Operating points lie at its intersection with each unit curve.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 320,
                  child: LineChart(
                    LineChartData(
                      minX: 0,
                      maxX: maxP * 1.1,
                      minY: 0,
                      maxY: maxIcr * 1.15,
                      lineBarsData: lineBarsData,
                      extraLinesData: ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: lambda,
                            color: Colors.indigoAccent,
                            strokeWidth: 2,
                            dashArray: [5, 5],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              labelResolver: (line) => ' λ = ${lambda.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.indigoAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          axisNameWidget: const Text('Generator Power P_G (MW)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (val, meta) => Text(val.toInt().toString(), style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                        leftTitles: AxisTitles(
                          axisNameWidget: const Text('ICR (\$/MWh)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 36,
                            getTitlesWidget: (val, meta) => Text(val.toStringAsFixed(1), style: const TextStyle(fontSize: 10)),
                          ),
                        ),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: true,
                        getDrawingHorizontalLine: (val) => FlLine(color: isDark ? Colors.white12 : Colors.black12, strokeWidth: 1),
                        getDrawingVerticalLine: (val) => FlLine(color: isDark ? Colors.white12 : Colors.black12, strokeWidth: 1),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < state.units.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(color: _unitColors[i % _unitColors.length], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(state.units[i].name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 14, height: 2, color: Colors.indigoAccent),
                        const SizedBox(width: 6),
                        const Text('System Marginal Cost λ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 3: Iteration Steps Inspector
  // ---------------------------------------------------------------------------
  Widget _buildStepsTab(
    BuildContext context,
    EconomicDispatchState state,
    ThemeData theme,
    bool isDark,
  ) {
    if (state.includeLosses) {
      final lossR = state.lossResult;
      if (lossR == null || lossR.iterations.isEmpty) {
        return const Center(child: Text('No loss iterations recorded.'));
      }

      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lossR.iterations.length,
        itemBuilder: (context, index) {
          final it = lossR.iterations[index];
          final isLast = index == lossR.iterations.length - 1;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: isLast && lossR.converged ? Colors.green : Colors.transparent),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Iteration ${it.iteration}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('λ = ${it.lambda.toStringAsFixed(4)} \$/MWh', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generation sum: ${it.totalPower.toStringAsFixed(2)} MW   ·   Loss: ${it.loss.toStringAsFixed(3)} MW   ·   Mismatch Er: ${it.error.toStringAsFixed(4)} MW',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                  const Divider(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: it.powers.entries.map((entry) {
                      final pf = it.penaltyFactors[entry.key] ?? 1.0;
                      return Chip(
                        label: Text('${entry.key}: ${entry.value.toStringAsFixed(1)} MW (L=${pf.toStringAsFixed(3)})', style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    final lr = state.losslessResult;
    if (lr == null || lr.steps.isEmpty) {
      return const Center(child: Text('No iteration steps recorded.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lr.steps.length,
      itemBuilder: (context, index) {
        final step = lr.steps[index];
        final isLast = index == lr.steps.length - 1;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isLast ? Colors.green : Colors.transparent),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pass ${step.iteration}: Limit Enforcement', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('λ = ${step.lambda.toStringAsFixed(4)} \$/MWh', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.indigoAccent)),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Unconstrained units: ${step.unconstrainedGenerators.join(", ")}', style: const TextStyle(fontSize: 12)),
                if (step.clampedGenerators.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Clamped units: ${step.clampedGenerators.entries.map((e) => "${e.key} @ ${e.value.toStringAsFixed(1)} MW").join(", ")}', style: const TextStyle(fontSize: 12, color: Colors.deepOrangeAccent)),
                  ),
                if (step.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final note in step.notes)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.amber.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                      child: Text(note, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNumberField(String label, double val, ValueChanged<double> onChanged) {
    return TextFormField(
      initialValue: val.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Tab 4: Examination Step-by-Step Hand Calculation Walkthrough
  // ---------------------------------------------------------------------------
  Widget _buildExamStepByStepTab(
    BuildContext context,
    EconomicDispatchState state,
    ThemeData theme,
    bool isDark,
  ) {
    final activeUnits = state.units.where((u) => u.isActive).toList();
    if (activeUnits.isEmpty) {
      return const Center(child: Text('No active generator units to solve.'));
    }

    final pDemand = state.demand;
    final includeLosses = state.includeLosses;

    // Intermediate analytical sums
    double sumInvTwoGamma = 0.0;
    double sumBetaOverTwoGamma = 0.0;

    for (final u in activeUnits) {
      final twoGamma = 2.0 * u.gamma;
      if (twoGamma > 0) {
        sumInvTwoGamma += 1.0 / twoGamma;
        sumBetaOverTwoGamma += u.beta / twoGamma;
      }
    }

    final unconstrainedLambda = sumInvTwoGamma > 0
        ? (pDemand + sumBetaOverTwoGamma) / sumInvTwoGamma
        : 0.0;

    // Dispatched powers and final lambda
    final finalLambda = includeLosses
        ? (state.lossResult?.lambda ?? unconstrainedLambda)
        : (state.losslessResult?.lambda ?? unconstrainedLambda);

    final finalPowers = includeLosses
        ? (state.lossResult?.powers ?? {})
        : (state.losslessResult?.powers ?? {});

    final totalCost = includeLosses
        ? (state.lossResult?.totalCost ?? 0.0)
        : (state.losslessResult?.totalCost ?? 0.0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Exam Scenario Banner Card
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
                            'EE4530 Examination Working: Economic Dispatch',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            'Step-by-step analytical derivation for examination hand calculations',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text(
                        includeLosses ? 'LOSSY (B-MATRIX)' : 'LOSSLESS (EQUAL SLOPE)',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: includeLosses
                          ? Colors.purple.withValues(alpha: 0.15)
                          : Colors.teal.withValues(alpha: 0.15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Given System Demand: P_D = ${pDemand.toStringAsFixed(1)} MW   ·   Active Units: ${activeUnits.length}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // STEP 1: Formulate Incremental Fuel Cost (ICR)
        _buildExamStepCard(
          stepNumber: 1,
          title: 'Formulate Incremental Fuel Cost (ICR) Equations',
          objective: 'Differentiate each unit quadratic fuel cost function to obtain the equal incremental cost condition.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _formulaBox(
                r'\text{Equal Slope Criterion: } \quad \frac{dC_i}{dP_i} = \beta_i + 2\gamma_i P_i = \lambda',
              ),
              const SizedBox(height: 10),
              const Text(
                'Applying the derivative to each thermal generator in the network:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...activeUnits.asMap().entries.map((entry) {
                final i = entry.key;
                final u = entry.value;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.black26 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${u.name}: ',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      Expanded(
                        child: Text(
                          'ICR_${i + 1} = ${u.beta.toStringAsFixed(3)} + ${(2.0 * u.gamma).toStringAsFixed(4)}·P_${i + 1} = λ',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.blueAccent),
                        ),
                      ),
                      Text(
                        'limits: [${u.pMin.toStringAsFixed(0)}, ${u.pMax.toStringAsFixed(0)}] MW',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 2: Invert to Express P_i(lambda)
        _buildExamStepCard(
          stepNumber: 2,
          title: 'Express Generator Power as a Function of System Lambda P_i(λ)',
          objective: 'Rearrange each marginal cost equation to express power P_i in terms of λ.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _formulaBox(
                r'P_i(\lambda) = \frac{\lambda - \beta_i}{2\gamma_i} = \left(\frac{1}{2\gamma_i}\right)\lambda - \left(\frac{\beta_i}{2\gamma_i}\right)',
              ),
              const SizedBox(height: 10),
              ...activeUnits.asMap().entries.map((entry) {
                final i = entry.key;
                final u = entry.value;
                final twoG = 2.0 * u.gamma;
                final invTwoG = twoG > 0 ? 1.0 / twoG : 0.0;
                final betaOverTwoG = twoG > 0 ? u.beta / twoG : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'P_${i + 1}(λ) = (λ - ${u.beta.toStringAsFixed(3)}) / ${twoG.toStringAsFixed(4)} = ${invTwoG.toStringAsFixed(3)}·λ - ${betaOverTwoG.toStringAsFixed(3)}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 3: Substitute into Power Balance and Solve for Lambda*
        _buildExamStepCard(
          stepNumber: 3,
          title: 'Substitute into Power Balance Equation & Solve for λ*',
          objective: 'Equate the total generation sum to the required demand to solve for the unconstrained system λ*.',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _formulaBox(
                r'\sum_{i=1}^N P_i(\lambda) = P_D \implies \lambda^* = \frac{P_D + \sum_{i=1}^N \frac{\beta_i}{2\gamma_i}}{\sum_{i=1}^N \frac{1}{2\gamma_i}}',
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
                      '• Sum of slopes:  Σ [1 / (2γ_i)] = ${sumInvTwoGamma.toStringAsFixed(4)}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Sum of intercepts:  Σ [β_i / (2γ_i)] = ${sumBetaOverTwoGamma.toStringAsFixed(4)} MW',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '• Numerator:  P_D + Σ [β_i / (2γ_i)] = ${pDemand.toStringAsFixed(1)} + ${sumBetaOverTwoGamma.toStringAsFixed(4)} = ${(pDemand + sumBetaOverTwoGamma).toStringAsFixed(4)} MW',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const Divider(height: 16),
                    Text(
                      'λ^* = ${(pDemand + sumBetaOverTwoGamma).toStringAsFixed(4)} / ${sumInvTwoGamma.toStringAsFixed(4)} = ${unconstrainedLambda.toStringAsFixed(4)} \$/MWh',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 4: Calculate Individual Power Allocations & Check Limits
        _buildExamStepCard(
          stepNumber: 4,
          title: 'Calculate Individual Allocations & Check Physical Limits',
          objective: 'Substitute λ* back into each generator formula and verify against [P_min, P_max].',
          theme: theme,
          isDark: isDark,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...activeUnits.asMap().entries.map((entry) {
                final i = entry.key;
                final u = entry.value;
                final twoG = 2.0 * u.gamma;
                final pUnconstrained = twoG > 0 ? (unconstrainedLambda - u.beta) / twoG : 0.0;
                final isViolatedMin = pUnconstrained < u.pMin;
                final isViolatedMax = pUnconstrained > u.pMax;
                final isViolated = isViolatedMin || isViolatedMax;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isViolated
                        ? (isDark ? Colors.red.withValues(alpha: 0.15) : Colors.red.shade50)
                        : (isDark ? Colors.green.withValues(alpha: 0.1) : Colors.green.shade50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isViolated ? Colors.redAccent : Colors.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isViolated ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                        color: isViolated ? Colors.redAccent : Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'P_${i + 1} = (${unconstrainedLambda.toStringAsFixed(4)} - ${u.beta.toStringAsFixed(3)}) / ${twoG.toStringAsFixed(4)} = ${pUnconstrained.toStringAsFixed(2)} MW',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 12),
                            ),
                            Text(
                              isViolated
                                  ? (isViolatedMin
                                      ? 'VIOLATION: ${pUnconstrained.toStringAsFixed(2)} < P_min (${u.pMin.toStringAsFixed(0)} MW) → Clamp to P_min!'
                                      : 'VIOLATION: ${pUnconstrained.toStringAsFixed(2)} > P_max (${u.pMax.toStringAsFixed(0)} MW) → Clamp to P_max!')
                                  : 'Within physical bounds [${u.pMin.toStringAsFixed(0)}, ${u.pMax.toStringAsFixed(0)}] MW',
                              style: TextStyle(
                                fontSize: 11,
                                color: isViolated ? Colors.redAccent : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // STEP 5: Final Dispatched Solution & Total Cost
        _buildExamStepCard(
          stepNumber: 5,
          title: 'Final Dispatched Operating Points & Total Operating Cost',
          objective: 'Present the final converged dispatch vector and compute the total hourly fuel expenditure.',
          theme: theme,
          isDark: isDark,
          isHighlighted: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Final Cleared System Marginal Cost (λ):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          '${finalLambda.toStringAsFixed(4)} \$/MWh',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'monospace', color: Colors.blueAccent),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    ...activeUnits.asMap().entries.map((entry) {
                      final i = entry.key;
                      final u = entry.value;
                      final pFinal = finalPowers[u.id] ?? 0.0;
                      final unitCost = u.alpha + u.beta * pFinal + u.gamma * pFinal * pFinal;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${u.name} (P_${i + 1}):', style: const TextStyle(fontSize: 12)),
                            Text(
                              '${pFinal.toStringAsFixed(2)} MW  (C_${i + 1} = \$${unitCost.toStringAsFixed(2)}/hr)',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total Hourly Fuel Cost (C_total):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(
                          '\$${totalCost.toStringAsFixed(2)} / hr',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            fontFamily: 'monospace',
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // STEP 6: Lossy Dispatch (Only if losses included)
        if (includeLosses) ...[
          const SizedBox(height: 16),
          _buildExamStepCard(
            stepNumber: 6,
            title: 'Transmission Loss Coordination with Kron B-Matrix',
            objective: 'Compute transmission losses and apply penalty factors in accordance with the coordination equations.',
            theme: theme,
            isDark: isDark,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _formulaBox(
                  r'P_L = \sum_i \sum_j P_i B_{ij} P_j \quad \text{and} \quad L_i = \frac{1}{1 - \frac{\partial P_L}{\partial P_i}} \implies L_i \frac{dC_i}{dP_i} = \lambda',
                ),
                const SizedBox(height: 10),
                Text(
                  'Total Transmission Losses: P_L = ${(state.lossResult?.transmissionLoss ?? 0.0).toStringAsFixed(3)} MW',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Generation Required: Σ P_G = ${(pDemand + (state.lossResult?.transmissionLoss ?? 0.0)).toStringAsFixed(2)} MW',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildExamStepCard({
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

  Widget _formulaBox(String tex) {
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
