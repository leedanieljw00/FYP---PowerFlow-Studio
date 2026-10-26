import 'package:flutter/material.dart';

import '../../../../core/math/power_flow_common.dart';
import '../../models/sld_bus_node.dart';
import '../../models/sld_line_branch.dart';

/// Modal bottom sheet displaying detailed telemetry and electrical state for a selected bus.
class BusInspectorSheet extends StatelessWidget {
  const BusInspectorSheet({
    super.key,
    required this.bus,
    this.mvaBase = 100.0,
    this.onEdit,
    this.onDelete,
    this.onConnect,
  });

  final SldBusNode bus;
  final double mvaBase;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final void Function(int busNumber)? onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final typeBadgeColor = switch (bus.type) {
      BusType.slack => const Color(0xFF7C4DFF),
      BusType.pv => bus.isQClamped ? Colors.deepOrangeAccent : const Color(0xFFFF9100),
      BusType.pq => const Color(0xFF00B0FF),
    };

    final typeBadgeLabel = switch (bus.type) {
      BusType.slack => 'SLACK BUS (REFERENCE)',
      BusType.pv => bus.isQClamped ? 'PV BUS (CLAMPED TO PQ)' : 'PV BUS (GENERATOR)',
      BusType.pq => 'PQ BUS (LOAD)',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header with bus number and classification
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bus.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeBadgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: typeBadgeColor.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          typeBadgeLabel,
                          style: TextStyle(
                            color: typeBadgeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Edit Equipment', style: TextStyle(fontSize: 12)),
                        onPressed: onEdit,
                      ),
                    if (onConnect != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Connect Branch from Bus ${bus.busNumber}',
                        icon: const Icon(Icons.add_link, color: Colors.cyanAccent),
                        onPressed: () => onConnect!(bus.busNumber),
                      ),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Remove Bus',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: onDelete,
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Card 1: Voltage State (|V| and angle)
            _buildSectionCard(
              theme: theme,
              isDark: isDark,
              title: 'Voltage State',
              icon: Icons.flash_on,
              iconColor: Colors.amber,
              child: Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Magnitude |V_i|',
                      value: '${bus.vMag.toStringAsFixed(4)} pu',
                      subtitle: '${(bus.vMag * 100.0).toStringAsFixed(2)}% nominal',
                      highlightColor: (bus.vMag < 0.95 || bus.vMag > 1.05)
                          ? Colors.orange
                          : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricTile(
                      label: 'Phase Angle δ_i',
                      value: '${bus.angleDeg.toStringAsFixed(3)}°',
                      subtitle: '${(bus.angleDeg * 3.14159265 / 180.0).toStringAsFixed(4)} rad',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Card 2: Net Scheduled Injections
            _buildSectionCard(
              theme: theme,
              isDark: isDark,
              title: 'Net Electrical Injection (P_i + jQ_i)',
              icon: Icons.compare_arrows,
              iconColor: Colors.cyan,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Net Real P_net',
                          value: '${(bus.pNet * mvaBase).toStringAsFixed(2)} MW',
                          subtitle: '${bus.pNet.toStringAsFixed(4)} pu',
                          highlightColor: bus.pNet >= 0 ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricTile(
                          label: 'Net Reactive Q_net',
                          value: '${(bus.qNet * mvaBase).toStringAsFixed(2)} MVAR',
                          subtitle: '${bus.qNet.toStringAsFixed(4)} pu',
                          highlightColor: bus.qNet >= 0 ? Colors.green : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Generation: P_G = ${(bus.pGen * mvaBase).toStringAsFixed(1)} MW, Q_G = ${(bus.qGen * mvaBase).toStringAsFixed(1)} MVAR',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Load Demand: P_D = ${(bus.pLoad * mvaBase).toStringAsFixed(1)} MW, Q_D = ${(bus.qLoad * mvaBase).toStringAsFixed(1)} MVAR',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Card 3: PV Reactive Capability Bounds (if PV bus)
            if (bus.type == BusType.pv || bus.qMin != null || bus.qMax != null) ...[
              const SizedBox(height: 12),
              _buildSectionCard(
                theme: theme,
                isDark: isDark,
                title: 'PV Reactive Limits [Q_min, Q_max]',
                icon: Icons.tune,
                iconColor: Colors.deepOrange,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Operating Status:',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: bus.isQClamped
                                ? Colors.red.withValues(alpha: 0.15)
                                : Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: bus.isQClamped ? Colors.red : Colors.green,
                            ),
                          ),
                          child: Text(
                            bus.isQClamped ? 'CLAMPED TO PQ (LIMIT HIT)' : 'NORMAL VOLTAGE REGULATION',
                            style: TextStyle(
                              color: bus.isQClamped ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Q_min: ${((bus.qMin ?? 0.0) * mvaBase).toStringAsFixed(1)} MVAR',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                        Text(
                          'Q_gen: ${(bus.qGen * mvaBase).toStringAsFixed(1)} MVAR',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: Colors.amber,
                          ),
                        ),
                        Text(
                          'Q_max: ${((bus.qMax ?? 0.0) * mvaBase).toStringAsFixed(1)} MVAR',
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildQProgressBar(bus),
                  ],
                ),
              ),
            ],

            if (onDelete != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text('Remove Bus ${bus.busNumber} from Canvas'),
                  onPressed: onDelete,
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildQProgressBar(SldBusNode bus) {
    final qMin = bus.qMin ?? -0.5;
    final qMax = bus.qMax ?? 1.0;
    final range = qMax - qMin;
    final progress = range > 1e-6 ? ((bus.qGen - qMin) / range).clamp(0.0, 1.0) : 0.5;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: progress,
        minHeight: 8,
        backgroundColor: Colors.grey.withValues(alpha: 0.2),
        valueColor: AlwaysStoppedAnimation<Color>(
          bus.isQClamped ? Colors.redAccent : Colors.amber,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required ThemeData theme,
    required bool isDark,
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    String? subtitle,
    Color? highlightColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: highlightColor,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ],
    );
  }
}

/// Modal bottom sheet displaying line telemetry and branch parameters.
class LineInspectorSheet extends StatelessWidget {
  const LineInspectorSheet({
    super.key,
    required this.line,
    this.mvaBase = 100.0,
    this.onEdit,
    this.onDelete,
  });

  final SldLineBranch line;
  final double mvaBase;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final pLossMW = line.pLoss * mvaBase;
    final qLossMvar = line.qLoss * mvaBase;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Branch: Bus ${line.fromBus} ➔ Bus ${line.toBus}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line.isTransformer
                            ? 'Transformer Branch (Tap a = ${line.tap.toStringAsFixed(3)})'
                            : 'Transmission Line (π-equivalent model)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.cyanAccent : Colors.blueAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onEdit != null)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Edit Branch', style: TextStyle(fontSize: 12)),
                        onPressed: onEdit,
                      ),
                    if (onDelete != null) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Delete Line',
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                        onPressed: onDelete,
                      ),
                    ],
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Card 1: Branch Parameters
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Line Electrical Parameters (p.u.)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _paramTile('Resistance R', '${line.r.toStringAsFixed(5)} pu'),
                      ),
                      Expanded(
                        child: _paramTile('Reactance X', '${line.x.toStringAsFixed(5)} pu'),
                      ),
                      Expanded(
                        child: _paramTile('Shunt B/2', '${line.bHalf.toStringAsFixed(5)} pu'),
                      ),
                      Expanded(
                        child: _paramTile('Tap a', line.tap.toStringAsFixed(3)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Card 2: Forward & Reverse Power Flows
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Power Flow Telemetry',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _paramTile(
                          'Sending End S_${line.fromBus}${line.toBus}',
                          '${(line.pFromTo * mvaBase).toStringAsFixed(2)} MW\n${(line.qFromTo * mvaBase).toStringAsFixed(2)} MVAR',
                          color: Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _paramTile(
                          'Receiving End S_${line.toBus}${line.fromBus}',
                          '${(line.pToFrom * mvaBase).toStringAsFixed(2)} MW\n${(line.qToFrom * mvaBase).toStringAsFixed(2)} MVAR',
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _paramTile(
                          'Active Loss P_loss',
                          '${pLossMW.toStringAsFixed(3)} MW',
                          color: Colors.redAccent,
                        ),
                      ),
                      Expanded(
                        child: _paramTile(
                          'Reactive Loss Q_loss',
                          '${qLossMvar.toStringAsFixed(3)} MVAR',
                          color: Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _paramTile(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: color,
          ),
        ),
      ],
    );
  }
}
