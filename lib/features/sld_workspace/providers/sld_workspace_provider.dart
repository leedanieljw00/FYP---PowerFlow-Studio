import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/complex.dart';
import '../../../core/math/power_flow_common.dart';
import '../../../core/utils/format.dart';
import '../../power_flow/models/bus_model.dart';
import '../../power_flow/models/line_model.dart';
import '../../power_flow/providers/power_flow_provider.dart';
import '../models/sld_bus_node.dart';
import '../models/sld_line_branch.dart';

enum PresetTopology {
  twoBus('2-Bus System', 'Generator to Load Benchmark'),
  threeBus('3-Bus Saadat', 'EE4530 Standard 3-Bus Looped Network'),
  ieee14Bus('IEEE 14-Bus', 'Standard Multi-Bus Benchmark Network'),
  sandbox('Custom Sandbox', 'Interactive Grid Builder & Editor');

  const PresetTopology(this.title, this.description);
  final String title;
  final String description;
}

enum SldEditorMode {
  select('Select', Icons.touch_app),
  addBus('Add Bus', Icons.add_circle_outline),
  connect('Connect', Icons.timeline),
  moveBus('Move', Icons.open_with),
  delete('Remove', Icons.delete_outline);

  const SldEditorMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SldWorkspaceState {
  const SldWorkspaceState({
    required this.currentPreset,
    required this.buses,
    required this.lines,
    this.selectedBusNumber,
    this.selectedLineId,
    this.showPowerFlowBadges = true,
    this.showDirectionArrows = true,
    this.showVoltages = true,
    this.showLosses = true,
    this.editorMode = SldEditorMode.select,
    this.connectingFromBusNumber,
    this.customBusPositions = const {},
  });

  final PresetTopology currentPreset;
  final List<SldBusNode> buses;
  final List<SldLineBranch> lines;
  final int? selectedBusNumber;
  final String? selectedLineId;
  final bool showPowerFlowBadges;
  final bool showDirectionArrows;
  final bool showVoltages;
  final bool showLosses;
  final SldEditorMode editorMode;
  final int? connectingFromBusNumber;
  final Map<int, Offset> customBusPositions;

  SldBusNode? get selectedBus {
    if (selectedBusNumber == null) return null;
    try {
      return buses.firstWhere((b) => b.busNumber == selectedBusNumber);
    } catch (_) {
      return null;
    }
  }

  SldLineBranch? get selectedLine {
    if (selectedLineId == null) return null;
    try {
      return lines.firstWhere((l) => l.id == selectedLineId);
    } catch (_) {
      return null;
    }
  }

  SldWorkspaceState copyWith({
    PresetTopology? currentPreset,
    List<SldBusNode>? buses,
    List<SldLineBranch>? lines,
    int? Function()? selectedBusNumber,
    String? Function()? selectedLineId,
    bool? showPowerFlowBadges,
    bool? showDirectionArrows,
    bool? showVoltages,
    bool? showLosses,
    SldEditorMode? editorMode,
    int? Function()? connectingFromBusNumber,
    Map<int, Offset>? customBusPositions,
  }) {
    return SldWorkspaceState(
      currentPreset: currentPreset ?? this.currentPreset,
      buses: buses ?? this.buses,
      lines: lines ?? this.lines,
      selectedBusNumber: selectedBusNumber != null ? selectedBusNumber() : this.selectedBusNumber,
      selectedLineId: selectedLineId != null ? selectedLineId() : this.selectedLineId,
      showPowerFlowBadges: showPowerFlowBadges ?? this.showPowerFlowBadges,
      showDirectionArrows: showDirectionArrows ?? this.showDirectionArrows,
      showVoltages: showVoltages ?? this.showVoltages,
      showLosses: showLosses ?? this.showLosses,
      editorMode: editorMode ?? this.editorMode,
      connectingFromBusNumber: connectingFromBusNumber != null
          ? connectingFromBusNumber()
          : this.connectingFromBusNumber,
      customBusPositions: customBusPositions ?? this.customBusPositions,
    );
  }
}

class SldWorkspaceNotifier extends Notifier<SldWorkspaceState> {
  @override
  SldWorkspaceState build() {
    final pfState = ref.watch(powerFlowProvider);
    final preset = stateOrNull?.currentPreset ?? PresetTopology.threeBus;
    return _buildSynchronizedState(preset, pfState);
  }

  /// Preset coordinates for layout on a virtual diagram canvas
  static const Map<int, Offset> _coords2Bus = {
    1: Offset(320, 420),
    2: Offset(800, 420),
  };

  static const Map<int, Offset> _coords3Bus = {
    1: Offset(320, 260),
    2: Offset(840, 260),
    3: Offset(580, 600),
  };

  static const Map<int, Offset> _coords14Bus = {
    1: Offset(180, 180),
    2: Offset(420, 180),
    3: Offset(760, 180),
    4: Offset(480, 400),
    5: Offset(220, 400),
    6: Offset(220, 640),
    7: Offset(720, 400),
    8: Offset(940, 400),
    9: Offset(720, 640),
    10: Offset(940, 640),
    11: Offset(460, 640),
    12: Offset(220, 860),
    13: Offset(460, 860),
    14: Offset(720, 860),
  };

  /// Constructs an SLD state synchronized with the given PowerFlowState
  SldWorkspaceState _buildSynchronizedState(PresetTopology preset, PowerFlowState pfState) {
    final Map<int, Offset> coordMap = switch (preset) {
      PresetTopology.twoBus => _coords2Bus,
      PresetTopology.threeBus => _coords3Bus,
      PresetTopology.ieee14Bus => _coords14Bus,
      PresetTopology.sandbox => stateOrNull?.customBusPositions ?? const {},
    };

    final savedPositions = Map<int, Offset>.from(stateOrNull?.customBusPositions ?? {});
    final sldBuses = <SldBusNode>[];

    for (var i = 0; i < pfState.buses.length; i++) {
      final b = pfState.buses[i];
      // Check saved custom positions first, then preset coordinates, then compute grid offset
      final pos = savedPositions[b.busNumber] ??
          coordMap[b.busNumber] ??
          Offset(260.0 + (i % 4) * 280.0, 240.0 + (i ~/ 4) * 240.0);

      savedPositions[b.busNumber] = pos;

      double vMag = b.vMag;
      double angleDeg = b.angleDeg;
      double pGen = b.pGen;
      double qGen = b.qGen;
      bool isClamped = false;

      // Enrich with solved power flow result if available
      final res = pfState.result;
      if (res != null && i < res.voltages.length) {
        final v = res.voltages[i];
        vMag = v.abs;
        angleDeg = v.arg * kDegPerRad;
        pGen = res.pGen[i];
        qGen = res.qGen[i];
        if (i < res.finalBusTypes.length) {
          isClamped = b.type == BusType.pv && res.finalBusTypes[i] == BusType.pq;
        }
      }

      sldBuses.add(SldBusNode(
        busNumber: b.busNumber,
        name: b.name,
        type: b.type,
        position: pos,
        isVertical: false,
        length: 88.0,
        vMag: vMag,
        angleDeg: angleDeg,
        pGen: pGen,
        qGen: qGen,
        pLoad: b.pLoad,
        qLoad: b.qLoad,
        qMin: b.qMin,
        qMax: b.qMax,
        isQClamped: isClamped,
      ));
    }

    final sldLines = <SldLineBranch>[];
    for (var k = 0; k < pfState.lines.length; k++) {
      final line = pfState.lines[k];
      Complex? sFromTo;
      Complex? sToFrom;
      Complex? loss;

      final res = pfState.result;
      if (res != null && k < res.lineFlows.length) {
        final flow = res.lineFlows[k];
        sFromTo = flow.sFromTo;
        sToFrom = flow.sToFrom;
        loss = flow.loss;
      }

      sldLines.add(SldLineBranch(
        id: line.id,
        fromBus: line.fromBus,
        toBus: line.toBus,
        r: line.r,
        x: line.x,
        bHalf: line.bHalf,
        tap: line.tap,
        sFromTo: sFromTo,
        sToFrom: sToFrom,
        loss: loss,
      ));
    }

    return SldWorkspaceState(
      currentPreset: preset,
      buses: sldBuses,
      lines: sldLines,
      selectedBusNumber: stateOrNull?.selectedBusNumber,
      selectedLineId: stateOrNull?.selectedLineId,
      showPowerFlowBadges: stateOrNull?.showPowerFlowBadges ?? true,
      showDirectionArrows: stateOrNull?.showDirectionArrows ?? true,
      showVoltages: stateOrNull?.showVoltages ?? true,
      showLosses: stateOrNull?.showLosses ?? true,
      editorMode: stateOrNull?.editorMode ?? SldEditorMode.select,
      connectingFromBusNumber: stateOrNull?.connectingFromBusNumber,
      customBusPositions: savedPositions,
    );
  }

  /// Load a preset topology and synchronize both SLD and PowerFlow providers
  void loadPreset(PresetTopology preset) {
    final pfNotifier = ref.read(powerFlowProvider.notifier);
    if (preset == PresetTopology.sandbox) {
      // Sandbox mode starts completely blank (0 buses, 0 lines)
      state = state.copyWith(
        currentPreset: PresetTopology.sandbox,
        customBusPositions: const {},
        selectedBusNumber: () => null,
        selectedLineId: () => null,
        buses: const [],
        lines: const [],
      );
      pfNotifier.loadSandboxPreset(
        customBuses: const <BusModel>[],
        customLines: const <LineModel>[],
      );
      return;
    }

    switch (preset) {
      case PresetTopology.twoBus:
        pfNotifier.load2BusPreset();
        break;
      case PresetTopology.threeBus:
        pfNotifier.load3BusPreset();
        break;
      case PresetTopology.ieee14Bus:
        pfNotifier.load14BusPreset();
        break;
      case PresetTopology.sandbox:
        break;
    }
    // Auto-calculate power flow on preset load for immediate interactive visualization
    pfNotifier.calculate();

    final pfState = ref.read(powerFlowProvider);
    state = _buildSynchronizedState(preset, pfState);
  }

  // ---------------------------------------------------------------------------
  // Sandbox Interactive Editing Operations
  // ---------------------------------------------------------------------------

  void setEditorMode(SldEditorMode mode) {
    state = state.copyWith(
      editorMode: mode,
      connectingFromBusNumber: () => null,
    );
  }

  void startConnecting(int fromBusNumber) {
    state = state.copyWith(
      connectingFromBusNumber: () => fromBusNumber,
      editorMode: SldEditorMode.connect,
    );
  }

  void cancelConnecting() {
    state = state.copyWith(
      connectingFromBusNumber: () => null,
    );
  }

  /// Creates a new transmission branch between two buses
  bool connectBuses({
    required int fromBus,
    required int toBus,
    double r = 0.02,
    double x = 0.05,
    double bHalf = 0.0,
    double tap = 1.0,
  }) {
    state = state.copyWith(
      connectingFromBusNumber: () => null,
    );
    if (fromBus == toBus) return false;

    // Check if line already exists between them
    final pfState = ref.read(powerFlowProvider);
    final exists = pfState.lines.any(
      (l) => (l.fromBus == fromBus && l.toBus == toBus) ||
          (l.fromBus == toBus && l.toBus == fromBus),
    );
    if (exists) return false;

    final lineId = 'line_${fromBus}_${toBus}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    final line = LineModel(
      id: lineId,
      fromBus: fromBus,
      toBus: toBus,
      r: r,
      x: x,
      bHalf: bHalf,
      tap: tap,
    );

    ref.read(powerFlowProvider.notifier).addCustomLine(line);
    state = state.copyWith(
      connectingFromBusNumber: () => null,
      currentPreset: PresetTopology.sandbox,
    );
    return true;
  }

  /// Adds a custom bus bar with optional generator and load equipment
  void addCustomBus({
    required Offset position,
    required String name,
    required BusType type,
    double vMag = 1.0,
    double angleDeg = 0.0,
    double pGen = 0.0,
    double qGen = 0.0,
    double pLoad = 0.0,
    double qLoad = 0.0,
    double? qMin,
    double? qMax,
    bool isVertical = false,
  }) {
    final pfState = ref.read(powerFlowProvider);
    final nextNum = pfState.buses.isEmpty
        ? 1
        : pfState.buses.map((b) => b.busNumber).reduce((a, b) => a > b ? a : b) + 1;

    final busModel = BusModel(
      id: 'bus_$nextNum',
      busNumber: nextNum,
      name: name.isNotEmpty ? name : 'Bus $nextNum (${type.label})',
      type: type,
      vMag: vMag,
      angleDeg: angleDeg,
      pGen: pGen,
      qGen: qGen,
      pLoad: pLoad,
      qLoad: qLoad,
      qMin: qMin,
      qMax: qMax,
    );

    final updatedPositions = Map<int, Offset>.from(state.customBusPositions);
    updatedPositions[nextNum] = position;

    ref.read(powerFlowProvider.notifier).addCustomBus(busModel);

    state = state.copyWith(
      customBusPositions: updatedPositions,
      currentPreset: PresetTopology.sandbox,
      selectedBusNumber: () => nextNum,
    );
  }

  /// Updates electrical parameters and generator/load equipment for an existing bus
  void updateBusEquipment({
    required int busNumber,
    String? name,
    BusType? type,
    double? vMag,
    double? angleDeg,
    double? pGen,
    double? qGen,
    double? pLoad,
    double? qLoad,
    double? Function()? qMin,
    double? Function()? qMax,
    bool? isVertical,
  }) {
    final pfState = ref.read(powerFlowProvider);
    final busIdx = pfState.buses.indexWhere((b) => b.busNumber == busNumber);
    if (busIdx == -1) return;

    final current = pfState.buses[busIdx];
    final updated = current.copyWith(
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
    );

    ref.read(powerFlowProvider.notifier).updateBus(busIdx, updated);

    // If orientation changed, update the SLD bus list directly
    if (isVertical != null) {
      final sldIdx = state.buses.indexWhere((b) => b.busNumber == busNumber);
      if (sldIdx != -1) {
        final updatedSldBuses = List<SldBusNode>.from(state.buses);
        updatedSldBuses[sldIdx] = updatedSldBuses[sldIdx].copyWith(isVertical: isVertical);
        state = state.copyWith(buses: updatedSldBuses);
      }
    }
  }

  /// Moves a busbar node to a new location on the diagram canvas
  void moveBus(int busNumber, Offset newPosition) {
    // Snap to 25px engineering grid
    double snap(double v) => (v / 25.0).roundToDouble() * 25.0;
    final snapped = Offset(
      snap(newPosition.dx).clamp(60.0, 1340.0),
      snap(newPosition.dy).clamp(60.0, 1040.0),
    );

    final updatedPositions = Map<int, Offset>.from(state.customBusPositions);
    updatedPositions[busNumber] = snapped;

    final sldIdx = state.buses.indexWhere((b) => b.busNumber == busNumber);
    if (sldIdx != -1) {
      final updatedSldBuses = List<SldBusNode>.from(state.buses);
      updatedSldBuses[sldIdx] = updatedSldBuses[sldIdx].copyWith(position: snapped);
      state = state.copyWith(
        buses: updatedSldBuses,
        customBusPositions: updatedPositions,
      );
    }
  }

  /// Removes a bus from the network along with all its attached lines
  void removeBus(int busNumber) {
    final updatedPositions = Map<int, Offset>.from(state.customBusPositions)..remove(busNumber);
    ref.read(powerFlowProvider.notifier).removeBusByNumber(busNumber);
    state = state.copyWith(
      customBusPositions: updatedPositions,
      selectedBusNumber: () => null,
    );
  }

  /// Removes a transmission branch line
  void removeLine(String lineId) {
    ref.read(powerFlowProvider.notifier).removeLineById(lineId);
    state = state.copyWith(
      selectedLineId: () => null,
    );
  }

  /// Resets canvas to a completely blank Sandbox starting point
  void clearCanvasToSandbox() {
    state = state.copyWith(
      customBusPositions: const {},
      currentPreset: PresetTopology.sandbox,
      selectedBusNumber: () => null,
      selectedLineId: () => null,
      buses: const [],
      lines: const [],
    );

    ref.read(powerFlowProvider.notifier).loadSandboxPreset(
          customBuses: const <BusModel>[],
          customLines: const <LineModel>[],
        );
  }

  void selectBus(int? busNumber) {
    state = state.copyWith(
      selectedBusNumber: () => busNumber,
      selectedLineId: () => null,
    );
  }

  void selectLine(String? lineId) {
    state = state.copyWith(
      selectedLineId: () => lineId,
      selectedBusNumber: () => null,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      selectedBusNumber: () => null,
      selectedLineId: () => null,
    );
  }

  void togglePowerFlowBadges() {
    state = state.copyWith(showPowerFlowBadges: !state.showPowerFlowBadges);
  }

  void toggleDirectionArrows() {
    state = state.copyWith(showDirectionArrows: !state.showDirectionArrows);
  }

  void toggleVoltages() {
    state = state.copyWith(showVoltages: !state.showVoltages);
  }

  void toggleLosses() {
    state = state.copyWith(showLosses: !state.showLosses);
  }
}

final sldWorkspaceProvider =
    NotifierProvider<SldWorkspaceNotifier, SldWorkspaceState>(
  SldWorkspaceNotifier.new,
);
