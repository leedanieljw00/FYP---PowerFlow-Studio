import 'package:flutter/material.dart';

import '../../../../core/math/power_flow_common.dart';
import '../../models/sld_bus_node.dart';

/// Comprehensive modal dialog for creating a custom bus or editing existing bus equipment (generators, loads).
class CustomBusDialog extends StatefulWidget {
  const CustomBusDialog({
    super.key,
    this.busToEdit,
    this.initialPosition,
    this.nextBusNumber = 1,
    required this.onSave,
    this.onDelete,
    this.mvaBase = 100.0,
  });

  final SldBusNode? busToEdit;
  final Offset? initialPosition;
  final int nextBusNumber;
  final double mvaBase;

  final void Function({
    required int busNumber,
    required String name,
    required BusType type,
    required double vMag,
    required double angleDeg,
    required double pGen,
    required double qGen,
    required double pLoad,
    required double qLoad,
    required double? qMin,
    required double? qMax,
    required bool isVertical,
    required Offset position,
  }) onSave;

  final VoidCallback? onDelete;

  @override
  State<CustomBusDialog> createState() => _CustomBusDialogState();
}

class _CustomBusDialogState extends State<CustomBusDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _vMagController;
  late final TextEditingController _angleController;
  late final TextEditingController _pGenController;
  late final TextEditingController _qGenController;
  late final TextEditingController _qMinController;
  late final TextEditingController _qMaxController;
  late final TextEditingController _pLoadController;
  late final TextEditingController _qLoadController;

  late BusType _type;
  late bool _hasGenerator;
  late bool _hasLoad;
  late bool _isVertical;
  late int _busNumber;

  @override
  void initState() {
    super.initState();
    final b = widget.busToEdit;

    _busNumber = b?.busNumber ?? widget.nextBusNumber;
    _type = b?.type ?? BusType.pq;
    _isVertical = b?.isVertical ?? false;

    _hasGenerator = b?.hasGenerator ?? (_type == BusType.slack || _type == BusType.pv);
    _hasLoad = b?.hasLoad ?? (_type == BusType.pq);

    _nameController = TextEditingController(
      text: b?.name ?? 'Bus $_busNumber (${_type.label})',
    );
    _vMagController = TextEditingController(
      text: (b?.vMag ?? 1.0).toStringAsFixed(3),
    );
    _angleController = TextEditingController(
      text: (b?.angleDeg ?? 0.0).toStringAsFixed(1),
    );

    // Generator inputs in MW / MVAR
    final pGenMW = (b?.pGen ?? (_type == BusType.pv ? 0.5 : 0.0)) * widget.mvaBase;
    final qGenMW = (b?.qGen ?? 0.0) * widget.mvaBase;
    final qMinMW = (b?.qMin != null) ? b!.qMin! * widget.mvaBase : -50.0;
    final qMaxMW = (b?.qMax != null) ? b!.qMax! * widget.mvaBase : 100.0;

    _pGenController = TextEditingController(text: pGenMW.toStringAsFixed(1));
    _qGenController = TextEditingController(text: qGenMW.toStringAsFixed(1));
    _qMinController = TextEditingController(text: qMinMW.toStringAsFixed(1));
    _qMaxController = TextEditingController(text: qMaxMW.toStringAsFixed(1));

    // Load inputs in MW / MVAR
    final pLoadMW = (b?.pLoad ?? (_type == BusType.pq ? 0.6 : 0.0)) * widget.mvaBase;
    final qLoadMW = (b?.qLoad ?? (_type == BusType.pq ? 0.3 : 0.0)) * widget.mvaBase;

    _pLoadController = TextEditingController(text: pLoadMW.toStringAsFixed(1));
    _qLoadController = TextEditingController(text: qLoadMW.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _vMagController.dispose();
    _angleController.dispose();
    _pGenController.dispose();
    _qGenController.dispose();
    _qMinController.dispose();
    _qMaxController.dispose();
    _pLoadController.dispose();
    _qLoadController.dispose();
    super.dispose();
  }

  void _onTypeChanged(BusType newType) {
    setState(() {
      _type = newType;
      if (_nameController.text.contains('Bus $_busNumber')) {
        _nameController.text = 'Bus $_busNumber (${newType.label})';
      }
      if (newType == BusType.slack || newType == BusType.pv) {
        _hasGenerator = true;
      }
    });
  }

  void _submit() {
    final vMag = double.tryParse(_vMagController.text) ?? 1.0;
    final angle = double.tryParse(_angleController.text) ?? 0.0;

    double pGen = 0.0;
    double qGen = 0.0;
    double? qMin;
    double? qMax;

    if (_hasGenerator) {
      final pMW = double.tryParse(_pGenController.text) ?? 0.0;
      final qMvar = double.tryParse(_qGenController.text) ?? 0.0;
      pGen = pMW / widget.mvaBase;
      qGen = qMvar / widget.mvaBase;

      if (_type == BusType.pv) {
        final qMinMW = double.tryParse(_qMinController.text);
        final qMaxMW = double.tryParse(_qMaxController.text);
        qMin = qMinMW != null ? qMinMW / widget.mvaBase : null;
        qMax = qMaxMW != null ? qMaxMW / widget.mvaBase : null;
      }
    }

    double pLoad = 0.0;
    double qLoad = 0.0;
    if (_hasLoad) {
      final pMW = double.tryParse(_pLoadController.text) ?? 0.0;
      final qMvar = double.tryParse(_qLoadController.text) ?? 0.0;
      pLoad = pMW / widget.mvaBase;
      qLoad = qMvar / widget.mvaBase;
    }

    final pos = widget.busToEdit?.position ?? widget.initialPosition ?? const Offset(400, 300);

    widget.onSave(
      busNumber: _busNumber,
      name: _nameController.text.trim(),
      type: _type,
      vMag: vMag,
      angleDeg: angle,
      pGen: pGen,
      qGen: qGen,
      pLoad: pLoad,
      qLoad: qLoad,
      qMin: qMin,
      qMax: qMax,
      isVertical: _isVertical,
      position: pos,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.busToEdit != null;

    final typeColor = switch (_type) {
      BusType.slack => const Color(0xFF7C4DFF),
      BusType.pv => const Color(0xFFFF9100),
      BusType.pq => const Color(0xFF00B0FF),
    };

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dialog Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.hub_outlined, color: typeColor, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEditing ? 'Edit Bus & Equipment' : 'Add Custom Bus Node',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Bus $_busNumber · ${isEditing ? "Modify configuration" : "Place into Sandbox"}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Scrollable Content
              Expanded(
                child: ListView(
                  children: [
                    // Section 1: Bus Identification & Classification
                    _buildSectionHeader('1. Bus Identification & Type', Icons.badge_outlined, typeColor),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Bus Name',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<BusType>(
                            initialValue: _type,
                            decoration: const InputDecoration(
                              labelText: 'Bus Type',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: BusType.values.map((t) {
                              return DropdownMenuItem(
                                value: t,
                                child: Text(t.label),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) _onTypeChanged(val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Voltage & Angle
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _vMagController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Specified |V| (pu)',
                              hintText: '1.00',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: 'pu',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _angleController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Initial Angle δ (deg)',
                              hintText: '0.0',
                              border: OutlineInputBorder(),
                              isDense: true,
                              suffixText: '°',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Section 2: Generator Equipment
                    _buildEquipmentCard(
                      title: 'Generator Equipment',
                      icon: Icons.power_outlined,
                      accentColor: Colors.amber,
                      isEnabled: _hasGenerator,
                      onToggle: (val) {
                        setState(() {
                          _hasGenerator = val;
                          if (!val && _type == BusType.pv) {
                            _type = BusType.pq;
                          }
                        });
                      },
                      isDark: isDark,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _pGenController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Active Gen P_G',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    suffixText: 'MW',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _qGenController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Reactive Gen Q_G',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    suffixText: 'MVAR',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_type == BusType.pv) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _qMinController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Lower Limit Q_min',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      suffixText: 'MVAR',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    controller: _qMaxController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      labelText: 'Upper Limit Q_max',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      suffixText: 'MVAR',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 3: Load Equipment
                    _buildEquipmentCard(
                      title: 'Load Demand Equipment',
                      icon: Icons.electric_bolt_outlined,
                      accentColor: Colors.redAccent,
                      isEnabled: _hasLoad,
                      onToggle: (val) {
                        setState(() {
                          _hasLoad = val;
                        });
                      },
                      isDark: isDark,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pLoadController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Active Load P_D',
                                border: OutlineInputBorder(),
                                isDense: true,
                                suffixText: 'MW',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _qLoadController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Reactive Load Q_D',
                                border: OutlineInputBorder(),
                                isDense: true,
                                suffixText: 'MVAR',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Section 4: Physical Busbar Orientation
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Busbar Orientation',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('Horizontal')),
                              ButtonSegment(value: true, label: Text('Vertical')),
                            ],
                            selected: {_isVertical},
                            onSelectionChanged: (set) {
                              setState(() {
                                _isVertical = set.first;
                              });
                            },
                          ),
                        ),
                      ],
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
                      label: const Text('Delete Bus', style: TextStyle(color: Colors.redAccent)),
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
                        icon: Icon(isEditing ? Icons.check : Icons.add),
                        label: Text(isEditing ? 'Save Changes' : 'Add Bus to Canvas'),
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

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildEquipmentCard({
    required String title,
    required IconData icon,
    required Color accentColor,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required bool isDark,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEnabled
              ? accentColor.withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: isEnabled ? accentColor : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isEnabled ? null : Colors.grey,
                    ),
                  ),
                ],
              ),
              Switch(
                value: isEnabled,
                onChanged: onToggle,
                activeThumbColor: accentColor,
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 8),
            child,
          ],
        ],
      ),
    );
  }
}
