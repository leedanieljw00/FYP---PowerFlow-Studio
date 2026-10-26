import 'package:flutter/material.dart';

import '../../models/sld_bus_node.dart';
import '../../models/sld_line_branch.dart';

/// Modal dialog for connecting two buses with a transmission line branch or transformer.
class ConnectBusesDialog extends StatefulWidget {
  const ConnectBusesDialog({
    super.key,
    required this.buses,
    this.lineToEdit,
    this.initialFromBus,
    this.initialToBus,
    required this.onConnect,
    this.onDelete,
  });

  final List<SldBusNode> buses;
  final SldLineBranch? lineToEdit;
  final int? initialFromBus;
  final int? initialToBus;

  final void Function({
    required int fromBus,
    required int toBus,
    required double r,
    required double x,
    required double bHalf,
    required double tap,
  }) onConnect;

  final VoidCallback? onDelete;

  @override
  State<ConnectBusesDialog> createState() => _ConnectBusesDialogState();
}

class _ConnectBusesDialogState extends State<ConnectBusesDialog> {
  late int _fromBus;
  late int _toBus;
  late final TextEditingController _rController;
  late final TextEditingController _xController;
  late final TextEditingController _bHalfController;
  late final TextEditingController _tapController;
  bool _isTransformer = false;

  @override
  void initState() {
    super.initState();
    final l = widget.lineToEdit;

    final busNums = widget.buses.map((b) => b.busNumber).toList();
    int defaultFrom = widget.initialFromBus ?? (busNums.isNotEmpty ? busNums.first : 1);
    if (!busNums.contains(defaultFrom) && busNums.isNotEmpty) {
      defaultFrom = busNums.first;
    }
    _fromBus = l?.fromBus ?? defaultFrom;

    final otherNums = busNums.where((n) => n != _fromBus).toList();
    int defaultTo = widget.initialToBus ?? (otherNums.isNotEmpty ? otherNums.first : (busNums.length > 1 ? busNums[1] : 2));
    if (!busNums.contains(defaultTo) && busNums.isNotEmpty) {
      defaultTo = otherNums.isNotEmpty ? otherNums.first : busNums.last;
    }
    _toBus = l?.toBus ?? defaultTo;

    _isTransformer = l?.isTransformer ?? false;

    _rController = TextEditingController(text: (l?.r ?? 0.02).toStringAsFixed(4));
    _xController = TextEditingController(text: (l?.x ?? 0.05).toStringAsFixed(4));
    _bHalfController = TextEditingController(text: (l?.bHalf ?? 0.0).toStringAsFixed(4));
    _tapController = TextEditingController(text: (l?.tap ?? 1.0).toStringAsFixed(3));
  }

  @override
  void dispose() {
    _rController.dispose();
    _xController.dispose();
    _bHalfController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_fromBus == _toBus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending and receiving bus cannot be identical.')),
      );
      return;
    }

    final r = double.tryParse(_rController.text) ?? 0.02;
    final x = double.tryParse(_xController.text) ?? 0.05;
    final bHalf = double.tryParse(_bHalfController.text) ?? 0.0;
    final tap = _isTransformer ? (double.tryParse(_tapController.text) ?? 1.0) : 1.0;

    widget.onConnect(
      fromBus: _fromBus,
      toBus: _toBus,
      r: r,
      x: x,
      bHalf: bHalf,
      tap: tap,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.lineToEdit != null;

    final busNums = widget.buses.map((b) => b.busNumber).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.timeline, color: Colors.cyanAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEditing ? 'Edit Transmission Branch' : 'Connect Buses with Branch',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                isEditing ? 'Modify line parameters' : 'Create transmission line or transformer',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Form fields
              Expanded(
                child: ListView(
                  children: [
                    // Bus selection
                    const Text(
                      'Terminal Endpoints',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _fromBus,
                            decoration: const InputDecoration(
                              labelText: 'Sending Bus (From)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: busNums.map((bNum) {
                              return DropdownMenuItem(
                                value: bNum,
                                child: Text('Bus $bNum'),
                              );
                            }).toList(),
                            onChanged: isEditing
                                ? null
                                : (val) {
                                    if (val != null) setState(() => _fromBus = val);
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.arrow_forward, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _toBus,
                            decoration: const InputDecoration(
                              labelText: 'Receiving Bus (To)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: busNums.map((bNum) {
                              return DropdownMenuItem(
                                value: bNum,
                                child: Text('Bus $bNum'),
                              );
                            }).toList(),
                            onChanged: isEditing
                                ? null
                                : (val) {
                                    if (val != null) setState(() => _toBus = val);
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Electrical parameters
                    const Text(
                      'Line Impedance & Charging (Per Unit)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _rController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Resistance R',
                              hintText: '0.02',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: 'pu',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _xController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Reactance X',
                              hintText: '0.05',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: 'pu',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _bHalfController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Half-line Susceptance B/2',
                        hintText: '0.00',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: 'pu',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transformer tap toggle
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isTransformer
                              ? Colors.tealAccent.withValues(alpha: 0.5)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.tune, size: 18, color: Colors.tealAccent),
                                  SizedBox(width: 8),
                                  Text(
                                    'Transformer Tap Ratio',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                              Switch(
                                value: _isTransformer,
                                onChanged: (val) {
                                  setState(() => _isTransformer = val);
                                },
                                activeThumbColor: Colors.tealAccent,
                              ),
                            ],
                          ),
                          if (_isTransformer) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _tapController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Off-nominal Tap Ratio a (e.g. 0.98)',
                                hintText: '1.00',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 24),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isEditing && widget.onDelete != null)
                    TextButton.icon(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      label: const Text('Delete Line', style: TextStyle(color: Colors.redAccent)),
                      onPressed: () {
                        widget.onDelete?.call();
                        Navigator.of(context).pop();
                      },
                    )
                  else
                    const SizedBox.shrink(),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: Icon(isEditing ? Icons.check : Icons.add_link),
                        label: Text(isEditing ? 'Save Changes' : 'Connect Buses'),
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
