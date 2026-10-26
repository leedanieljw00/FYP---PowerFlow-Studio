import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/complex.dart';
import '../../../core/math/matrix.dart';
import '../../../core/math/power_flow_common.dart';
import '../../../core/utils/format.dart';
import '../providers/power_flow_provider.dart';

class StepInspectionScreen extends ConsumerStatefulWidget {
  const StepInspectionScreen({super.key});

  @override
  ConsumerState<StepInspectionScreen> createState() => _StepInspectionScreenState();
}

class _StepInspectionScreenState extends ConsumerState<StepInspectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showPolarYbus = false;

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
    final state = ref.watch(powerFlowProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final result = state.result;
    final ybus = state.ybus ?? result?.ybus;

    if (ybus == null && result == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Solution & Inspection')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assessment_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                'No solution calculated yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Configure your system and tap "Solve Power Flow" on the main tab.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run 3-Bus Saadat Benchmark'),
                onPressed: () {
                  ref.read(powerFlowProvider.notifier).load3BusPreset();
                  ref.read(powerFlowProvider.notifier).calculate();
                },
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result != null
                  ? '${result.method.label} Inspection'
                  : 'Y_bus Inspection',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (result != null)
              Text(
                result.converged
                    ? 'Converged in ${result.iterationCount} iterations (ε = ${fmtSci(result.options.tolerance, 1)})'
                    : 'Did not converge (Max mismatch: ${fmtSci(result.finalPowerMismatch)})',
                style: TextStyle(
                  fontSize: 12,
                  color: result.converged ? Colors.greenAccent : Colors.orangeAccent,
                ),
              ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on), text: 'Y_bus Matrix'),
            Tab(icon: Icon(Icons.timeline), text: 'Iteration Steps'),
            Tab(icon: Icon(Icons.table_chart), text: 'Final Summary'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildYbusView(context, ybus, isDark),
          _buildIterationsView(context, result, isDark),
          _buildSummaryView(context, result, isDark),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Y_bus View
  // ---------------------------------------------------------------------------
  Widget _buildYbusView(BuildContext context, ComplexMatrix? ybus, bool isDark) {
    if (ybus == null) {
      return const Center(child: Text('Y_bus not yet generated.'));
    }
    final n = ybus.rows;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bus Admittance Matrix [Y_bus]',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dimension: $n × $n buses   ·   Symmetric: ${ybus.isSymmetric() ? "Yes" : "No (tap ratio present)"}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Cartesian (G+jB)')),
                    ButtonSegment(value: true, label: Text('Polar (|Y|∠θ)')),
                  ],
                  selected: {_showPolarYbus},
                  onSelectionChanged: (set) {
                    setState(() {
                      _showPolarYbus = set.first;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                isDark ? Colors.grey.shade800 : Colors.blueGrey.shade100,
              ),
              columns: [
                const DataColumn(
                  label: Text('Row / Col', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (var j = 0; j < n; j++)
                  DataColumn(
                    label: Text(
                      'Bus ${j + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
              rows: [
                for (var i = 0; i < n; i++)
                  DataRow(
                    cells: [
                      DataCell(
                        Text('Bus ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      for (var j = 0; j < n; j++)
                        DataCell(
                          _buildYbusCell(ybus.get(i, j), i == j, isDark),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade900 : Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? Colors.amber.shade900 : Colors.amber.shade200,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Diagonal elements highlighted represent total self-admittances Y_ii (including shunt charging). Off-diagonal elements represent mutual admittances Y_ij = -y_ij.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildYbusCell(Complex z, bool isDiagonal, bool isDark) {
    final text = _showPolarYbus
        ? z.toPolarString(3)
        : z.toCartesianString(4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDiagonal
            ? (isDark ? Colors.blue.withAlpha(40) : Colors.blue.withAlpha(30))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: isDiagonal
            ? Border.all(color: Colors.blueAccent.withAlpha(100))
            : null,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: isDiagonal ? FontWeight.bold : FontWeight.normal,
          color: z.isZero
              ? Colors.grey
              : (isDiagonal ? Colors.blueAccent : null),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Iterations Inspector View
  // ---------------------------------------------------------------------------
  Widget _buildIterationsView(BuildContext context, PowerFlowResult? result, bool isDark) {
    if (result == null) {
      return const Center(child: Text('Please run the solver to inspect iterations.'));
    }

    final iters = result.iterations;
    if (iters.isEmpty) {
      return const Center(child: Text('No iterations recorded.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: iters.length,
      itemBuilder: (context, index) {
        final rec = iters[index];
        final isLast = index == iters.length - 1;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isLast && result.converged
                  ? Colors.green.shade400
                  : (isDark ? Colors.grey.shade800 : Colors.grey.shade300),
            ),
          ),
          child: ExpansionTile(
            initiallyExpanded: index == 0 || isLast,
            leading: CircleAvatar(
              backgroundColor: isLast && result.converged
                  ? Colors.green
                  : Colors.blueGrey,
              radius: 16,
              child: Text(
                '${rec.k}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              'Iteration ${rec.k}   ·   ${rec.errorLabel} = ${fmtSci(rec.maxError)} pu',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: Text(
              'Error limit: ε = ${fmtSci(result.options.tolerance, 1)} pu',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rec.notes.isNotEmpty) ...[
                      for (final note in rec.notes)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(30),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.orange.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.warning_amber, size: 16, color: Colors.orange),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(note, style: const TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                    ],
                    if (rec is NrIterationRecord)
                      _buildNrIterationDetails(context, rec, isDark)
                    else if (rec is GsIterationRecord)
                      _buildGsIterationDetails(context, rec, isDark),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNrIterationDetails(
      BuildContext context, NrIterationRecord nr, bool isDark) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mismatches and Step Updates
        Text(
          '1. Power Mismatches (ΔP, ΔQ) & Step Corrections (Δδ, Δ|V|)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 36,
            dataRowMinHeight: 32,
            dataRowMaxHeight: 36,
            columns: const [
              DataColumn(label: Text('Equation')),
              DataColumn(label: Text('Bus')),
              DataColumn(label: Text('P/Q Scheduled (pu)')),
              DataColumn(label: Text('P/Q Calculated (pu)')),
              DataColumn(label: Text('Mismatch (Δ)')),
              DataColumn(label: Text('Correction (Step)')),
            ],
            rows: [
              for (var i = 0; i < nr.angleBuses.length; i++)
                DataRow(
                  cells: [
                    const DataCell(Text('ΔP (Real)')),
                    DataCell(Text('Bus ${nr.angleBuses[i] + 1}')),
                    DataCell(Text(fmtNum(nr.pScheduled[i]))),
                    DataCell(Text(fmtNum(nr.pCalculated[i]))),
                    DataCell(Text(
                      fmtNum(nr.deltaP[i]),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: nr.deltaP[i].abs() > 0.001 ? Colors.amber.shade700 : null,
                      ),
                    )),
                    DataCell(Text(
                      'Δδ = ${fmtNum(nr.dAngle[i] * kDegPerRad, 4)}° (${fmtNum(nr.dAngle[i], 5)} rad)',
                      style: const TextStyle(fontFamily: 'monospace'),
                    )),
                  ],
                ),
              for (var i = 0; i < nr.magBuses.length; i++)
                DataRow(
                  cells: [
                    const DataCell(Text('ΔQ (Reactive)')),
                    DataCell(Text('Bus ${nr.magBuses[i] + 1}')),
                    DataCell(Text(fmtNum(nr.qScheduled[i]))),
                    DataCell(Text(fmtNum(nr.qCalculated[i]))),
                    DataCell(Text(
                      fmtNum(nr.deltaQ[i]),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: nr.deltaQ[i].abs() > 0.001 ? Colors.amber.shade700 : null,
                      ),
                    )),
                    DataCell(Text(
                      'Δ|V| = ${fmtNum(nr.dVmag[i], 5)} pu',
                      style: const TextStyle(fontFamily: 'monospace'),
                    )),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full Numerical Jacobian
        Text(
          '2. Full Numerical Jacobian Matrix J [size: ${nr.size} × ${nr.size}]',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          'J = [[J1: ∂P/∂δ, J2: ∂P/∂|V|], [J3: ∂Q/∂δ, J4: ∂Q/∂|V|]]',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        _buildJacobianGrid(nr, isDark),
        const SizedBox(height: 16),

        // Voltages after this iteration
        Text(
          '3. Bus Voltages After Iteration ${nr.k}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < nr.vMag.length; i++)
                Container(
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bus ${i + 1} (${nr.busTypes[i].label})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('|V| = ${fmtNum(nr.vMag[i], 4)} pu', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text('δ = ${fmtNum(nr.angle[i] * kDegPerRad, 4)}°', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildJacobianGrid(NrIterationRecord nr, bool isDark) {
    final jac = nr.jacobian;
    final na = nr.na;
    final size = nr.size;

    // Row labels: ΔP_i then ΔQ_i
    final rowLabels = <String>[
      for (final b in nr.angleBuses) 'ΔP${sub(b + 1)}',
      for (final b in nr.magBuses) 'ΔQ${sub(b + 1)}',
    ];

    // Col labels: Δδ_i then Δ|V|_i
    final colLabels = <String>[
      for (final b in nr.angleBuses) 'Δδ${sub(b + 1)}',
      for (final b in nr.magBuses) 'Δ|V|${sub(b + 1)}',
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columns: [
            const DataColumn(label: Text('Row / Col', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            for (var c = 0; c < size; c++)
              DataColumn(
                label: Text(
                  colLabels[c],
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: c < na ? Colors.indigoAccent : Colors.teal,
                  ),
                ),
              ),
          ],
          rows: [
            for (var r = 0; r < size; r++)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      rowLabels[r],
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: r < na ? Colors.indigoAccent : Colors.teal,
                      ),
                    ),
                  ),
                  for (var c = 0; c < size; c++)
                    DataCell(
                      Text(
                        fmtNum(jac.get(r, c), 4),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGsIterationDetails(
      BuildContext context, GsIterationRecord gs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Bus Voltages & Successive Updates',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Bus')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Previous V')),
              DataColumn(label: Text('Updated V')),
              DataColumn(label: Text('|ΔV| Step')),
              DataColumn(label: Text('Q Gen / Inj')),
            ],
            rows: [
              for (var i = 0; i < gs.vAfter.length; i++)
                DataRow(
                  cells: [
                    DataCell(Text('Bus ${i + 1}')),
                    DataCell(Text(gs.busTypes[i].label)),
                    DataCell(Text(
                      gs.vBefore[i].toPolarString(4),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    )),
                    DataCell(Text(
                      gs.vAfter[i].toPolarString(4),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.bold),
                    )),
                    DataCell(Text(
                      fmtNum(gs.deltaV[i], 5),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    )),
                    DataCell(Text(
                      gs.qInjection.containsKey(i)
                          ? '${fmtNum(gs.qInjection[i]!, 4)} pu'
                          : '—',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    )),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Final Summary View
  // ---------------------------------------------------------------------------
  Widget _buildSummaryView(BuildContext context, PowerFlowResult? result, bool isDark) {
    if (result == null) {
      return const Center(child: Text('Please run the solver to view convergence summary.'));
    }

    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: result.converged
                ? (isDark ? Colors.green.shade900.withAlpha(80) : Colors.green.shade50)
                : (isDark ? Colors.orange.shade900.withAlpha(80) : Colors.orange.shade50),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: result.converged ? Colors.green : Colors.orange,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    result.converged ? Icons.check_circle : Icons.error_outline,
                    color: result.converged ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    result.converged ? 'Power Flow Converged' : 'Power Flow Incomplete',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: result.converged ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(result.message, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              Text(
                'Algorithm: ${result.method.label}   ·   Iterations: ${result.iterationCount}   ·   Tolerance: ${fmtSci(result.options.tolerance, 1)} pu',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Bus Voltages & Injections Table
        Text(
          'Bus Operating State & Power Balance',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Bus')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('|V| (pu)')),
                DataColumn(label: Text('Angle (°)'), numeric: true),
                DataColumn(label: Text('P Gen (pu)'), numeric: true),
                DataColumn(label: Text('Q Gen (pu)'), numeric: true),
                DataColumn(label: Text('P Load (pu)'), numeric: true),
                DataColumn(label: Text('Q Load (pu)'), numeric: true),
              ],
              rows: [
                for (var i = 0; i < result.buses.length; i++)
                  DataRow(
                    cells: [
                      DataCell(Text('Bus ${i + 1}')),
                      DataCell(Text(result.finalBusTypes[i].label)),
                      DataCell(Text(fmtNum(result.vMag[i], 4), style: const TextStyle(fontWeight: FontWeight.bold))),
                      DataCell(Text(fmtNum(result.angle[i] * kDegPerRad, 3))),
                      DataCell(Text(fmtNum(result.pGen[i], 4))),
                      DataCell(Text(fmtNum(result.qGen[i], 4))),
                      DataCell(Text(fmtNum(result.buses[i].pLoad, 4))),
                      DataCell(Text(fmtNum(result.buses[i].qLoad, 4))),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Line Flows & Losses Table
        Text(
          'Branch Power Flows & Transmission Losses',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Line')),
                DataColumn(label: Text('From → To')),
                DataColumn(label: Text('P_ij (pu)'), numeric: true),
                DataColumn(label: Text('Q_ij (pu)'), numeric: true),
                DataColumn(label: Text('P_ji (pu)'), numeric: true),
                DataColumn(label: Text('Q_ji (pu)'), numeric: true),
                DataColumn(label: Text('P Loss (pu)'), numeric: true),
                DataColumn(label: Text('Q Loss (pu)'), numeric: true),
              ],
              rows: [
                for (final flow in result.lineFlows)
                  DataRow(
                    cells: [
                      DataCell(Text('Line ${flow.branchIndex + 1}')),
                      DataCell(Text('${flow.from + 1} → ${flow.to + 1}')),
                      DataCell(Text(fmtNum(flow.sFromTo.re, 4))),
                      DataCell(Text(fmtNum(flow.sFromTo.im, 4))),
                      DataCell(Text(fmtNum(flow.sToFrom.re, 4))),
                      DataCell(Text(fmtNum(flow.sToFrom.im, 4))),
                      DataCell(Text(
                        fmtNum(flow.loss.re, 4),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                      )),
                      DataCell(Text(
                        fmtNum(flow.loss.im, 4),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent),
                      )),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // System Wide Totals
        Text(
          'Total System Power Balance',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildTotalCard(
                'Total Generation',
                'P: ${fmtNum(result.totalGeneration.re, 4)} pu',
                'Q: ${fmtNum(result.totalGeneration.im, 4)} pu',
                Colors.teal,
                isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTotalCard(
                'Total Load',
                'P: ${fmtNum(result.totalLoad.re, 4)} pu',
                'Q: ${fmtNum(result.totalLoad.im, 4)} pu',
                Colors.indigo,
                isDark,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildTotalCard(
                'Total Losses',
                'P_loss: ${fmtNum(result.totalLoss.re, 4)} pu',
                'Q_loss: ${fmtNum(result.totalLoss.im, 4)} pu',
                Colors.deepOrange,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTotalCard(
      String title, String line1, String line2, Color accent, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 6),
          Text(line1, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          Text(line2, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}
