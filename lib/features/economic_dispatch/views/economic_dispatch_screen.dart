import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildConfigurationTab(context, state, notifier, theme, isDark),
          _buildChartTab(context, state, theme, isDark),
          _buildStepsTab(context, state, theme, isDark),
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
}
