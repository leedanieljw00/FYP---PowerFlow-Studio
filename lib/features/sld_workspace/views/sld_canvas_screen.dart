import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/power_flow_common.dart';
import '../../power_flow/models/line_model.dart';
import '../../power_flow/providers/power_flow_provider.dart';
import '../models/sld_bus_node.dart';
import '../models/sld_line_branch.dart';
import '../painters/sld_grid_painter.dart';
import '../providers/sld_workspace_provider.dart';
import 'widgets/bus_inspector_sheet.dart';
import 'widgets/connect_buses_dialog.dart';
import 'widgets/custom_bus_dialog.dart';

/// Interactive Single-Line Diagram (SLD) Schematic Canvas and Sandbox Grid Editor.
class SldCanvasScreen extends ConsumerStatefulWidget {
  const SldCanvasScreen({super.key});

  @override
  ConsumerState<SldCanvasScreen> createState() => _SldCanvasScreenState();
}

class _SldCanvasScreenState extends ConsumerState<SldCanvasScreen>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformController;
  late final AnimationController _flowAnimController;

  int? _draggingBusNumber;
  Offset? _dragTouchOffset;
  Offset? _liveConnectPoint;
  Offset? _lastPointerPos;

  final Set<int> _activeTouchPointers = {};
  double _lastScale = 1.0;
  bool _isNavigatingGrid = false;

  @override
  void initState() {
    super.initState();
    _transformController = TransformationController();
    _flowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    // In live runtime, repeat smoothly; in automated widget tests, set a static phase to prevent pumpAndSettle timeouts
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      _flowAnimController.repeat();
    } else {
      _flowAnimController.value = 0.5;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resetView();
    });
  }

  @override
  void dispose() {
    _flowAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _resetView() {
    final media = MediaQuery.of(context).size;
    final scale = (media.width / 1200.0).clamp(0.65, 1.15);
    final matrix = Matrix4.identity()
      ..storage[0] = scale
      ..storage[5] = scale
      ..storage[12] = 40.0
      ..storage[13] = 40.0;
    _transformController.value = matrix;
    setState(() {});
  }

  void _zoom(double factor) {
    final media = MediaQuery.of(context).size;
    final center = Offset(media.width / 2.0, media.height / 2.0);
    _applyZoomAt(center, factor);
  }

  void _applyZoomAt(Offset focalPoint, double ratio, [Matrix4? targetMatrix]) {
    final matrix = targetMatrix ?? _transformController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final newScale = (currentScale * ratio).clamp(0.2, 4.0);
    final k = newScale / currentScale;

    final fx = focalPoint.dx;
    final fy = focalPoint.dy;

    final tx = matrix.storage[12];
    final ty = matrix.storage[13];

    matrix.storage[0] *= k;
    matrix.storage[5] *= k;
    matrix.storage[12] = fx * (1.0 - k) + tx * k;
    matrix.storage[13] = fy * (1.0 - k) + ty * k;

    _transformController.value = matrix;
    setState(() {});
  }

  void _handleCanvasTap(TapUpDetails details) {
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final sldState = ref.read(sldWorkspaceProvider);

    // Convert local screen/viewport coordinates into virtual scene space
    final scenePoint = _transformController.toScene(details.localPosition);

    // 1. ADD BUS MODE: Tap canvas to drop a custom bus at that location
    if (sldState.editorMode == SldEditorMode.addBus) {
      _openAddBusDialog(initialPos: scenePoint);
      return;
    }

    // 2. CONNECT MODE: Tap first bus, then second bus to connect them
    if (sldState.editorMode == SldEditorMode.connect) {
      for (final bus in sldState.buses) {
        if (bus.hitTest(scenePoint)) {
          if (sldState.connectingFromBusNumber == null) {
            sldNotifier.startConnecting(bus.busNumber);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Selected Bus ${bus.busNumber}. Now tap destination bus to link them.'),
                duration: const Duration(seconds: 2),
              ),
            );
          } else if (sldState.connectingFromBusNumber != bus.busNumber) {
            _openConnectDialog(
              fromBus: sldState.connectingFromBusNumber!,
              toBus: bus.busNumber,
            );
          } else {
            sldNotifier.cancelConnecting();
            setState(() => _liveConnectPoint = null);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cancelled connection.')),
            );
          }
          return;
        }
      }
      // Tapped empty space in connect mode cancels current selection
      if (sldState.connectingFromBusNumber != null) {
        sldNotifier.cancelConnecting();
        setState(() => _liveConnectPoint = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cancelled connection.')),
        );
      }
      return;
    }

    // 3. MOVE BUS MODE: Tap bus selects it
    if (sldState.editorMode == SldEditorMode.moveBus) {
      for (final bus in sldState.buses) {
        if (bus.hitTest(scenePoint)) {
          sldNotifier.selectBus(bus.busNumber);
          return;
        }
      }
      sldNotifier.clearSelection();
      return;
    }

    // 4. REMOVE / DELETE MODE: Tap bus or line to delete
    if (sldState.editorMode == SldEditorMode.delete) {
      for (final bus in sldState.buses) {
        if (bus.hitTest(scenePoint)) {
          sldNotifier.removeBus(bus.busNumber);
          final remaining = ref.read(powerFlowProvider).buses.length;
          if (remaining >= 2) {
            ref.read(powerFlowProvider.notifier).calculate();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed Bus ${bus.busNumber} and attached branches.'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      }

      // Check if any line was tapped
      final busMap = <int, SldBusNode>{};
      for (final b in sldState.buses) {
        busMap[b.busNumber] = b;
      }

      for (final line in sldState.lines) {
        final f = busMap[line.fromBus];
        final t = busMap[line.toBus];
        if (f == null || t == null) continue;

        if (line.hitTest(scenePoint, f.position, t.position)) {
          sldNotifier.removeLine(line.id);
          final remaining = ref.read(powerFlowProvider).buses.length;
          if (remaining >= 2) {
            ref.read(powerFlowProvider.notifier).calculate();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Removed Branch Line ${line.fromBus} -> ${line.toBus}.'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
      }
      return;
    }

    // 5. SELECT / INSPECT MODE (Default)
    // Check if any bus was tapped
    for (final bus in sldState.buses) {
      if (bus.hitTest(scenePoint)) {
        sldNotifier.selectBus(bus.busNumber);
        _showBusInspector(bus);
        return;
      }
    }

    // Check if any line was tapped
    final busMap = <int, SldBusNode>{};
    for (final b in sldState.buses) {
      busMap[b.busNumber] = b;
    }

    for (final line in sldState.lines) {
      final f = busMap[line.fromBus];
      final t = busMap[line.toBus];
      if (f == null || t == null) continue;

      if (line.hitTest(scenePoint, f.position, t.position)) {
        sldNotifier.selectLine(line.id);
        _showLineInspector(line);
        return;
      }
    }

    // Tapped empty canvas: clear selection
    sldNotifier.clearSelection();
  }

  void _openAddBusDialog({Offset? initialPos}) {
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final pfState = ref.read(powerFlowProvider);
    final nextNum = pfState.buses.isEmpty
        ? 1
        : pfState.buses.map((b) => b.busNumber).reduce((a, b) => a > b ? a : b) + 1;

    showDialog(
      context: context,
      builder: (ctx) => CustomBusDialog(
        initialPosition: initialPos ?? const Offset(500, 350),
        nextBusNumber: nextNum,
        onSave: ({
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
        }) {
          sldNotifier.addCustomBus(
            position: position,
            name: name,
            type: type,
            vMag: vMag,
            angleDeg: angleDeg,
            pGen: pGen,
            qGen: qGen,
            pLoad: pLoad,
            qLoad: qLoad,
            qMin: qMin,
            qMax: qMax,
            isVertical: isVertical,
          );
          final pfStateAfter = ref.read(powerFlowProvider);
          if (pfStateAfter.buses.length >= 2 && pfStateAfter.lines.isNotEmpty) {
            ref.read(powerFlowProvider.notifier).calculate();
          }
        },
      ),
    );
  }

  void _openConnectDialog({int? fromBus, int? toBus}) {
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final sldState = ref.read(sldWorkspaceProvider);
    final pfNotifier = ref.read(powerFlowProvider.notifier);

    // Cancel any active connecting indicator
    sldNotifier.cancelConnecting();
    setState(() => _liveConnectPoint = null);

    if (sldState.buses.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('At least 2 buses are required on the canvas before connecting them.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => ConnectBusesDialog(
        buses: sldState.buses,
        initialFromBus: fromBus,
        initialToBus: toBus,
        onConnect: ({
          required int fromBus,
          required int toBus,
          required double r,
          required double x,
          required double bHalf,
          required double tap,
        }) {
          final connected = sldNotifier.connectBuses(
            fromBus: fromBus,
            toBus: toBus,
            r: r,
            x: x,
            bHalf: bHalf,
            tap: tap,
          );
          if (!connected) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('A branch line between Bus $fromBus and Bus $toBus already exists.'),
                backgroundColor: Colors.orangeAccent,
              ),
            );
            return;
          }
          final pfStateAfter = ref.read(powerFlowProvider);
          if (pfStateAfter.buses.length >= 2) {
            pfNotifier.calculate();
          }
        },
      ),
    );
  }

  void _showBusInspector(SldBusNode bus) {
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final pfNotifier = ref.read(powerFlowProvider.notifier);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BusInspectorSheet(
        bus: bus,
        onEdit: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (dialogCtx) => CustomBusDialog(
              busToEdit: bus,
              onSave: ({
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
              }) {
                sldNotifier.updateBusEquipment(
                  busNumber: busNumber,
                  name: name,
                  type: type,
                  vMag: vMag,
                  angleDeg: angleDeg,
                  pGen: pGen,
                  qGen: qGen,
                  pLoad: pLoad,
                  qLoad: qLoad,
                  qMin: () => qMin,
                  qMax: () => qMax,
                  isVertical: isVertical,
                );
                pfNotifier.calculate();
              },
              onDelete: () {
                sldNotifier.removeBus(bus.busNumber);
                final remaining = ref.read(powerFlowProvider).buses.length;
                if (remaining >= 2) {
                  pfNotifier.calculate();
                }
              },
            ),
          );
        },
        onConnect: (busNum) {
          Navigator.of(context).pop();
          _openConnectDialog(fromBus: busNum);
        },
        onDelete: () {
          Navigator.of(context).pop();
          sldNotifier.removeBus(bus.busNumber);
          final remaining = ref.read(powerFlowProvider).buses.length;
          if (remaining >= 2) {
            pfNotifier.calculate();
          }
        },
      ),
    );
  }

  void _showLineInspector(SldLineBranch line) {
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final sldState = ref.read(sldWorkspaceProvider);
    final pfNotifier = ref.read(powerFlowProvider.notifier);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => LineInspectorSheet(
        line: line,
        onEdit: () {
          Navigator.of(context).pop();
          showDialog(
            context: context,
            builder: (dialogCtx) => ConnectBusesDialog(
              lineToEdit: line,
              buses: sldState.buses,
              onConnect: ({
                required int fromBus,
                required int toBus,
                required double r,
                required double x,
                required double bHalf,
                required double tap,
              }) {
                final updated = LineModel(
                  id: line.id,
                  fromBus: fromBus,
                  toBus: toBus,
                  r: r,
                  x: x,
                  bHalf: bHalf,
                  tap: tap,
                );
                pfNotifier.updateLineById(line.id, updated);
                pfNotifier.calculate();
              },
            ),
          );
        },
        onDelete: () {
          Navigator.of(context).pop();
          sldNotifier.removeLine(line.id);
          final remaining = ref.read(powerFlowProvider).buses.length;
          if (remaining >= 2) {
            pfNotifier.calculate();
          }
        },
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
    _isNavigatingGrid = false;
    _draggingBusNumber = null;
    _dragTouchOffset = null;

    final isTouch = _activeTouchPointers.isNotEmpty;
    final pointerCount = details.pointerCount;

    // 2 or more fingers on touchscreens -> always navigate (pan / pinch-zoom)
    if (isTouch && (pointerCount >= 2 || _activeTouchPointers.length >= 2)) {
      _isNavigatingGrid = true;
      return;
    }

    // Convert local viewport point into virtual scene coordinates
    final scenePoint = _transformController.toScene(details.localFocalPoint);
    _lastPointerPos = scenePoint;

    final sldState = ref.read(sldWorkspaceProvider);
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);

    // 1 finger: hit test to check if moving or interacting with any busbar
    for (final bus in sldState.buses) {
      if (bus.hitTest(scenePoint)) {
        _draggingBusNumber = bus.busNumber;
        _dragTouchOffset = scenePoint - bus.position;
        sldNotifier.selectBus(bus.busNumber);

        // If in Connect mode, initiate live rubber-band wire
        if (sldState.editorMode == SldEditorMode.connect &&
            sldState.connectingFromBusNumber == null) {
          sldNotifier.startConnecting(bus.busNumber);
          setState(() => _liveConnectPoint = scenePoint);
        }
        return;
      }
    }

    // Touch hit empty canvas:
    if (!isTouch) {
      // Desktop / Mouse drag on empty space navigates the grid
      _isNavigatingGrid = true;
    } else {
      // Touchscreen device: 1 finger on empty space does NOT pan grid!
      // (Requires 2 fingers to navigate around the grid)
      _isNavigatingGrid = false;
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    final isTouch = _activeTouchPointers.isNotEmpty;
    final pointerCount = details.pointerCount;

    // Switch to 2-finger navigation if a second touch joins mid-gesture
    if (isTouch && (pointerCount >= 2 || _activeTouchPointers.length >= 2)) {
      if (!_isNavigatingGrid) {
        _isNavigatingGrid = true;
        _draggingBusNumber = null;
        setState(() => _liveConnectPoint = null);
      }
    }

    // 1. Grid navigation (2 fingers on touch, or mouse drag on empty space)
    if (_isNavigatingGrid) {
      final matrix = _transformController.value.clone();
      matrix.storage[12] += details.focalPointDelta.dx;
      matrix.storage[13] += details.focalPointDelta.dy;

      final scaleRatio = details.scale / _lastScale;
      _lastScale = details.scale;

      if ((scaleRatio - 1.0).abs() > 0.002) {
        _applyZoomAt(details.localFocalPoint, scaleRatio, matrix);
      } else {
        _transformController.value = matrix;
        setState(() {});
      }
      return;
    }

    // 2. 1-finger bus manipulation
    final scenePoint = _transformController.toScene(details.localFocalPoint);
    _lastPointerPos = scenePoint;
    final sldState = ref.read(sldWorkspaceProvider);
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);

    // Case A: Move bus (Move mode or Select mode)
    if (_draggingBusNumber != null &&
        (sldState.editorMode == SldEditorMode.moveBus ||
         sldState.editorMode == SldEditorMode.select)) {
      final targetCenter = scenePoint - (_dragTouchOffset ?? Offset.zero);
      sldNotifier.moveBus(_draggingBusNumber!, targetCenter);
      return;
    }

    // Case B: Connect mode rubber-band wire
    if (sldState.editorMode == SldEditorMode.connect &&
        sldState.connectingFromBusNumber != null) {
      setState(() => _liveConnectPoint = scenePoint);
      return;
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    final sldState = ref.read(sldWorkspaceProvider);

    // If connect mode ended over a different destination bus:
    if (sldState.editorMode == SldEditorMode.connect &&
        sldState.connectingFromBusNumber != null &&
        _lastPointerPos != null) {
      for (final bus in sldState.buses) {
        if (bus.busNumber != sldState.connectingFromBusNumber &&
            bus.hitTest(_lastPointerPos!)) {
          _openConnectDialog(
            fromBus: sldState.connectingFromBusNumber!,
            toBus: bus.busNumber,
          );
          break;
        }
      }
    }

    setState(() {
      _draggingBusNumber = null;
      _dragTouchOffset = null;
      _liveConnectPoint = null;
      _isNavigatingGrid = false;
      _lastScale = 1.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sldState = ref.watch(sldWorkspaceProvider);
    final sldNotifier = ref.read(sldWorkspaceProvider.notifier);
    final pfState = ref.watch(powerFlowProvider);
    final pfNotifier = ref.read(powerFlowProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.hub_outlined, color: Colors.cyanAccent),
            const SizedBox(width: 10),
            Text(
              'SLD Schematic Canvas',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          // Topology preset dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<PresetTopology>(
                value: sldState.currentPreset,
                icon: const Icon(Icons.arrow_drop_down),
                onChanged: (PresetTopology? newPreset) {
                  if (newPreset != null) {
                    sldNotifier.loadPreset(newPreset);
                    _resetView();
                  }
                },
                items: PresetTopology.values.map((p) {
                  return DropdownMenuItem(
                    value: p,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p == PresetTopology.sandbox)
                          const Padding(
                            padding: EdgeInsets.only(right: 6),
                            child: Icon(Icons.dashboard_customize, size: 14, color: Colors.amber),
                          ),
                        Text(
                          p.title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: p == PresetTopology.sandbox ? Colors.amber : null,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Solve Power Flow button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: () {
                if (pfState.buses.length < 2) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('At least 2 buses and 1 transmission branch are required to solve power flow.'),
                      backgroundColor: Colors.orangeAccent,
                    ),
                  );
                  return;
                }
                pfNotifier.calculate();
                sldNotifier.loadPreset(sldState.currentPreset);
                if (pfState.errorMessage != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(pfState.errorMessage!),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                }
              },
              icon: Icon(
                pfState.result?.converged == true
                    ? Icons.check_circle_outline
                    : Icons.play_arrow,
                size: 16,
                color: pfState.result?.converged == true ? Colors.green : null,
              ),
              label: Text(
                pfState.result?.converged == true ? 'Solved' : 'Solve Flow',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Infinite Diagram Schematic Canvas & Multi-Touch Controller
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.touch) {
                  _activeTouchPointers.add(event.pointer);
                }
              },
              onPointerUp: (event) {
                if (event.kind == PointerDeviceKind.touch) {
                  _activeTouchPointers.remove(event.pointer);
                }
              },
              onPointerCancel: (event) {
                if (event.kind == PointerDeviceKind.touch) {
                  _activeTouchPointers.remove(event.pointer);
                }
              },
              onPointerSignal: (signal) {
                if (signal is PointerScrollEvent) {
                  final zoomFactor = signal.scrollDelta.dy < 0 ? 1.08 : 0.92;
                  _applyZoomAt(signal.localPosition, zoomFactor);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: _handleCanvasTap,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_transformController, _flowAnimController]),
                  builder: (context, _) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                        final visibleRect = SldGridPainter.computeSceneRect(
                          viewportSize,
                          _transformController.value,
                        );

                        return ClipRect(
                          child: CustomPaint(
                            size: viewportSize,
                            painter: SldGridPainter(
                              buses: sldState.buses,
                              lines: sldState.lines,
                              selectedBusNumber: sldState.selectedBusNumber,
                              selectedLineId: sldState.selectedLineId,
                              connectingFromBusNumber: sldState.connectingFromBusNumber,
                              liveConnectPoint: _liveConnectPoint,
                              isDark: isDark,
                              colorScheme: theme.colorScheme,
                              showPowerFlowBadges: sldState.showPowerFlowBadges,
                              showDirectionArrows: sldState.showDirectionArrows,
                              showVoltages: sldState.showVoltages,
                              showLosses: sldState.showLosses,
                              flowAnimation: _flowAnimController,
                              transformMatrix: _transformController.value,
                              visibleSceneRect: visibleRect,
                              repaint: _flowAnimController,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),

          // 1b. Empty Canvas Welcome Overlay (when 0 buses on canvas)
          if (sldState.buses.isEmpty)
            Center(
              child: _buildEmptyCanvasOverlay(isDark, sldNotifier),
            ),

          // 2. Sandbox Editor Mode Toolbar (Center Top)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: _buildSandboxToolbar(sldState, sldNotifier, isDark),
            ),
          ),

          // 3. Active Mode Notification Banner (if in interactive mode)
          if (sldState.editorMode != SldEditorMode.select)
            Positioned(
              top: 64,
              left: 0,
              right: 0,
              child: Center(
                child: _buildModeInstructionBanner(sldState, sldNotifier, isDark),
              ),
            ),

          // 4. Overlay controls (Badges, Flows, Voltages) - Left Top
          Positioned(
            top: 12,
            left: 12,
            child: _buildOverlayPillBar(sldState, sldNotifier, isDark),
          ),

          // 5. Floating Canvas Navigation Tools (Zoom In, Zoom Out, Reset) - Bottom Right
          Positioned(
            right: 16,
            bottom: 20,
            child: _buildCanvasControls(isDark),
          ),

          // 6. Schematic Legend - Bottom Left
          Positioned(
            left: 16,
            bottom: 20,
            child: _buildSchematicLegend(isDark),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Sandbox Editor Toolbar
  // ---------------------------------------------------------------------------

  Widget _buildSandboxToolbar(
    SldWorkspaceState state,
    SldWorkspaceNotifier notifier,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xE60F172A) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Select mode
            _toolModeButton(
              mode: SldEditorMode.select,
              activeMode: state.editorMode,
              onTap: () => notifier.setEditorMode(SldEditorMode.select),
            ),
            const SizedBox(width: 4),
            // Add Bus mode
            _toolModeButton(
              mode: SldEditorMode.addBus,
              activeMode: state.editorMode,
              onTap: () => notifier.setEditorMode(SldEditorMode.addBus),
            ),
            const SizedBox(width: 4),
            // Connect Line mode
            _toolModeButton(
              mode: SldEditorMode.connect,
              activeMode: state.editorMode,
              onTap: () => notifier.setEditorMode(SldEditorMode.connect),
            ),
            const SizedBox(width: 4),
            // Move Bus mode
            _toolModeButton(
              mode: SldEditorMode.moveBus,
              activeMode: state.editorMode,
              onTap: () => notifier.setEditorMode(SldEditorMode.moveBus),
            ),
            const SizedBox(width: 4),
            // Delete mode
            _toolModeButton(
              mode: SldEditorMode.delete,
              activeMode: state.editorMode,
              onTap: () => notifier.setEditorMode(SldEditorMode.delete),
            ),

            const SizedBox(width: 6),
            Container(
              height: 20,
              width: 1,
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
            const SizedBox(width: 6),

            // Quick Action: Clear to Blank Sandbox
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Reset to Blank Sandbox Slate',
              icon: const Icon(Icons.layers_clear_outlined, size: 18),
              onPressed: () {
                notifier.clearCanvasToSandbox();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Reset canvas to blank Sandbox.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolModeButton({
    required SldEditorMode mode,
    required SldEditorMode activeMode,
    required VoidCallback onTap,
  }) {
    final isSelected = mode == activeMode;
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 1.2)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode.icon,
              size: 16,
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              mode.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? theme.colorScheme.primary : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeInstructionBanner(
    SldWorkspaceState state,
    SldWorkspaceNotifier notifier,
    bool isDark,
  ) {
    String text = '';
    IconData icon = Icons.info_outline;

    switch (state.editorMode) {
      case SldEditorMode.addBus:
        text = 'Add Bus Mode: Tap anywhere on the blueprint grid to place a new bus node.';
        icon = Icons.add_circle_outline;
        break;
      case SldEditorMode.connect:
        if (state.connectingFromBusNumber == null) {
          text = 'Connect Mode: Tap the first busbar to start a branch connection.';
        } else {
          text = 'Connecting from Bus ${state.connectingFromBusNumber}: Tap destination busbar to link them.';
        }
        icon = Icons.timeline;
        break;
      case SldEditorMode.moveBus:
        text = 'Move Bus Mode: Drag any busbar node to reposition it on the grid.';
        icon = Icons.open_with;
        break;
      case SldEditorMode.delete:
        text = 'Remove Mode: Tap any busbar or branch line to delete it.';
        icon = Icons.delete_outline;
        break;
      case SldEditorMode.select:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF01E293B) : const Color(0xF2F1F5F9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => notifier.setEditorMode(SldEditorMode.select),
            child: const Icon(Icons.close, size: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayPillBar(
    SldWorkspaceState state,
    SldWorkspaceNotifier notifier,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _filterChip(
            label: 'Flows',
            isSelected: state.showPowerFlowBadges,
            onTap: notifier.togglePowerFlowBadges,
          ),
          const SizedBox(width: 4),
          _filterChip(
            label: 'Flow Motion',
            isSelected: state.showDirectionArrows,
            onTap: notifier.toggleDirectionArrows,
          ),
          const SizedBox(width: 4),
          _filterChip(
            label: 'Voltages',
            isSelected: state.showVoltages,
            onTap: notifier.toggleVoltages,
          ),
          const SizedBox(width: 4),
          _filterChip(
            label: 'Losses',
            isSelected: state.showLosses,
            onTap: notifier.toggleLosses,
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildCanvasControls(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: 'Zoom In',
            onPressed: () => _zoom(1.25),
          ),
          IconButton(
            icon: const Icon(Icons.remove, size: 20),
            tooltip: 'Zoom Out',
            onPressed: () => _zoom(0.8),
          ),
          const Divider(height: 1),
          IconButton(
            icon: const Icon(Icons.fit_screen, size: 20),
            tooltip: 'Reset Canvas View',
            onPressed: _resetView,
          ),
        ],
      ),
    );
  }

  Widget _buildSchematicLegend(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xD90F172A) : const Color(0xE6FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(const Color(0xFF7C4DFF), 'Slack'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFFFF9100), 'PV (Gen)'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFF00B0FF), 'PQ (Load)'),
          const SizedBox(width: 12),
          _legendItem(const Color(0xFF10B981), 'P Flow (MW)'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildEmptyCanvasOverlay(bool isDark, SldWorkspaceNotifier sldNotifier) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xF20F172A) : const Color(0xF8FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.cyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.grid_4x4_rounded,
              color: Colors.cyanAccent,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Blank Custom Sandbox',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Canvas is clear. Add custom busbars with generator and load equipment, then draw transmission branches to build your grid.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add_circle, size: 18),
                label: const Text('Add Busbar'),
                onPressed: () => _openAddBusDialog(),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.touch_app, size: 18),
                label: const Text('Add Mode'),
                onPressed: () => sldNotifier.setEditorMode(SldEditorMode.addBus),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
