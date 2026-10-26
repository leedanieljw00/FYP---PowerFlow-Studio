import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/power_flow_common.dart';
import '../models/bus_model.dart';
import '../models/line_model.dart';
import '../providers/power_flow_provider.dart';
import 'step_inspection_screen.dart';

class PowerFlowScreen extends ConsumerWidget {
  const PowerFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(powerFlowProvider);
    final notifier = ref.read(powerFlowProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PowerFlow Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('System Configuration & Solvers · EE4530', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          // Preset selector
          PopupMenuButton<String>(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: 'Load Presets',
            onSelected: (preset) {
              if (preset == '3bus') {
                notifier.load3BusPreset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded 3-Bus Saadat Benchmark Network')),
                );
              } else if (preset == '2bus') {
                notifier.load2BusPreset();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Loaded 2-Bus Simple Network')),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: '3bus',
                child: Text('3-Bus Saadat Network (Standard)'),
              ),
              const PopupMenuItem(
                value: '2bus',
                child: Text('2-Bus Generator & Load System'),
              ),
            ],
          ),
          // Solver options dialog
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Solver Settings',
            onPressed: () => _showSolverOptionsDialog(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Method Selection Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade50,
            child: Row(
              children: [
                const Text('Solver:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<PowerFlowMethod>(
                    segments: const [
                      ButtonSegment(
                        value: PowerFlowMethod.newtonRaphson,
                        label: Text('Newton–Raphson (NR)'),
                        icon: Icon(Icons.flash_on, size: 16),
                      ),
                      ButtonSegment(
                        value: PowerFlowMethod.gaussSeidel,
                        label: Text('Gauss–Seidel (GS)'),
                        icon: Icon(Icons.loop, size: 16),
                      ),
                    ],
                    selected: {state.selectedMethod},
                    onSelectionChanged: (set) => notifier.setMethod(set.first),
                  ),
                ),
              ],
            ),
          ),

          // Error banner if any
          if (state.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.red.shade900,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.errorMessage!,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // Convergence banner if solved
          if (state.result != null)
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StepInspectionScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: state.result!.converged ? Colors.teal.shade800 : Colors.orange.shade900,
                child: Row(
                  children: [
                    Icon(
                      state.result!.converged ? Icons.check_circle : Icons.warning,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${state.result!.converged ? "Converged" : "Completed"}: ${state.result!.iterationCount} iterations. Tap to inspect Y_bus, Jacobian & step updates →',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white),
                  ],
                ),
              ),
            ),

          // Buses and Lines Config List
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Buses Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Buses (${state.buses.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Bus'),
                      onPressed: () => notifier.addBus(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Bus Cards
                for (var i = 0; i < state.buses.length; i++)
                  _buildBusCard(context, ref, i, state.buses[i], isDark),

                const SizedBox(height: 20),

                // Lines Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Transmission Lines / Branches (${state.lines.length})',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Line'),
                      onPressed: () => notifier.addLine(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Line Cards
                for (var i = 0; i < state.lines.length; i++)
                  _buildLineCard(context, ref, i, state.lines[i], state.buses, isDark),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: state.isCalculating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  state.isCalculating ? 'Calculating...' : 'Solve Power Flow',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: state.isCalculating ? null : () => notifier.calculate(),
              ),
            ),
            if (state.result != null) ...[
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.visibility),
                label: const Text('Inspect'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StepInspectionScreen()),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bus Card
  // ---------------------------------------------------------------------------
  Widget _buildBusCard(
      BuildContext context, WidgetRef ref, int index, BusModel bus, bool isDark) {
    final notifier = ref.read(powerFlowProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Bus Header & Type
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _busTypeColor(bus.type),
                  child: Text(
                    '${bus.busNumber}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bus.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                // Bus Type Selector
                DropdownButton<BusType>(
                  value: bus.type,
                  underline: const SizedBox(),
                  items: BusType.values.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(
                        t.label,
                        style: TextStyle(
                          color: _busTypeColor(t),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (newType) {
                    if (newType != null) {
                      notifier.updateBus(index, bus.copyWith(type: newType));
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                  onPressed: () => notifier.removeBus(index),
                ),
              ],
            ),
            const Divider(height: 16),

            // Row 2: |V| and Angle
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: '|V| (pu)',
                    initialValue: bus.vMag,
                    onChanged: (val) => notifier.updateBus(index, bus.copyWith(vMag: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'Angle δ (°)',
                    initialValue: bus.angleDeg,
                    enabled: bus.type != BusType.slack,
                    onChanged: (val) => notifier.updateBus(index, bus.copyWith(angleDeg: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'P_Gen (pu)',
                    initialValue: bus.pGen,
                    enabled: bus.type != BusType.slack,
                    onChanged: (val) => notifier.updateBus(index, bus.copyWith(pGen: val)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Row 3: P_Load, Q_Load, and Q_limits (if PV)
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: 'P_Load (pu)',
                    initialValue: bus.pLoad,
                    onChanged: (val) => notifier.updateBus(index, bus.copyWith(pLoad: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'Q_Load (pu)',
                    initialValue: bus.qLoad,
                    onChanged: (val) => notifier.updateBus(index, bus.copyWith(qLoad: val)),
                  ),
                ),
                if (bus.type == BusType.pv) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildNumberField(
                      label: 'Q_min (pu)',
                      initialValue: bus.qMin ?? -0.5,
                      onChanged: (val) =>
                          notifier.updateBus(index, bus.copyWith(qMin: () => val)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildNumberField(
                      label: 'Q_max (pu)',
                      initialValue: bus.qMax ?? 1.0,
                      onChanged: (val) =>
                          notifier.updateBus(index, bus.copyWith(qMax: () => val)),
                    ),
                  ),
                ] else
                  const Spacer(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Line Card
  // ---------------------------------------------------------------------------
  Widget _buildLineCard(BuildContext context, WidgetRef ref, int index,
      LineModel line, List<BusModel> buses, bool isDark) {
    final notifier = ref.read(powerFlowProvider.notifier);
    final busNumbers = buses.map((b) => b.busNumber).toList();

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
                const Icon(Icons.compare_arrows, size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text('Line ${index + 1}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                // From bus dropdown
                DropdownButton<int>(
                  value: busNumbers.contains(line.fromBus) ? line.fromBus : busNumbers.first,
                  underline: const SizedBox(),
                  items: busNumbers.map((bNum) {
                    return DropdownMenuItem(value: bNum, child: Text('Bus $bNum'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      notifier.updateLine(index, line.copyWith(fromBus: val));
                    }
                  },
                ),
                const Text(' → '),
                // To bus dropdown
                DropdownButton<int>(
                  value: busNumbers.contains(line.toBus) ? line.toBus : busNumbers.last,
                  underline: const SizedBox(),
                  items: busNumbers.map((bNum) {
                    return DropdownMenuItem(value: bNum, child: Text('Bus $bNum'));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      notifier.updateLine(index, line.copyWith(toBus: val));
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                  onPressed: () => notifier.removeLine(index),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildNumberField(
                    label: 'R (pu)',
                    initialValue: line.r,
                    onChanged: (val) => notifier.updateLine(index, line.copyWith(r: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'X (pu)',
                    initialValue: line.x,
                    onChanged: (val) => notifier.updateLine(index, line.copyWith(x: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'B/2 (pu)',
                    initialValue: line.bHalf,
                    onChanged: (val) => notifier.updateLine(index, line.copyWith(bHalf: val)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberField(
                    label: 'Tap a',
                    initialValue: line.tap,
                    onChanged: (val) => notifier.updateLine(index, line.copyWith(tap: val)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper Widgets
  // ---------------------------------------------------------------------------
  Widget _buildNumberField({
    required String label,
    required double initialValue,
    required ValueChanged<double> onChanged,
    bool enabled = true,
  }) {
    return TextFormField(
      initialValue: initialValue.toString(),
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
      onChanged: (text) {
        final val = double.tryParse(text);
        if (val != null) onChanged(val);
      },
    );
  }

  Color _busTypeColor(BusType type) {
    return switch (type) {
      BusType.slack => Colors.purple,
      BusType.pv => Colors.teal,
      BusType.pq => Colors.indigo,
    };
  }

  void _showSolverOptionsDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(powerFlowProvider);
    final notifier = ref.read(powerFlowProvider.notifier);

    var tol = state.options.tolerance;
    var maxIter = state.options.maxIterations;
    var enforceQ = state.options.enforceQLimits;
    var alpha = state.options.accelerationFactor;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Solver Guardrails & Settings'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: tol.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Convergence Tolerance ε (pu)',
                        helperText: 'Default: 0.0001 (1e-4)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        final val = double.tryParse(v);
                        if (val != null && val > 0) tol = val;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: maxIter.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Max Iterations',
                        helperText: 'Default: 50 iterations',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final val = int.tryParse(v);
                        if (val != null && val > 0) maxIter = val;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: alpha.toString(),
                      decoration: const InputDecoration(
                        labelText: 'GS Acceleration Factor α',
                        helperText: '1.0 = none, typically 1.3 - 1.6',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) {
                        final val = double.tryParse(v);
                        if (val != null && val > 0) alpha = val;
                      },
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Enforce Q-Limits'),
                      subtitle: const Text('Convert PV to PQ buses on violation'),
                      value: enforceQ,
                      onChanged: (val) => setState(() => enforceQ = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    notifier.updateOptions(
                      SolverOptions(
                        tolerance: tol,
                        maxIterations: maxIter,
                        enforceQLimits: enforceQ,
                        accelerationFactor: alpha,
                      ),
                    );
                    Navigator.pop(ctx);
                  },
                  child: const Text('Save Settings'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
