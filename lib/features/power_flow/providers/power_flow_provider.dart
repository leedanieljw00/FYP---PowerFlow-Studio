import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/gauss_seidel.dart';
import '../../../core/math/matrix.dart';
import '../../../core/math/newton_raphson.dart';
import '../../../core/math/ybus_builder.dart';
import '../models/bus_model.dart';
import '../models/line_model.dart';

/// State of the Power Flow calculation and workspace.
class PowerFlowState {
  const PowerFlowState({
    required this.buses,
    required this.lines,
    this.selectedMethod = PowerFlowMethod.newtonRaphson,
    this.options = const SolverOptions(
      tolerance: 1e-4,
      maxIterations: 50,
      enforceQLimits: true,
      accelerationFactor: 1.0,
    ),
    this.ybus,
    this.result,
    this.errorMessage,
    this.isCalculating = false,
  });

  final List<BusModel> buses;
  final List<LineModel> lines;
  final PowerFlowMethod selectedMethod;
  final SolverOptions options;
  final ComplexMatrix? ybus;
  final PowerFlowResult? result;
  final String? errorMessage;
  final bool isCalculating;

  PowerFlowState copyWith({
    List<BusModel>? buses,
    List<LineModel>? lines,
    PowerFlowMethod? selectedMethod,
    SolverOptions? options,
    ComplexMatrix? Function()? ybus,
    PowerFlowResult? Function()? result,
    String? Function()? errorMessage,
    bool? isCalculating,
  }) {
    return PowerFlowState(
      buses: buses ?? this.buses,
      lines: lines ?? this.lines,
      selectedMethod: selectedMethod ?? this.selectedMethod,
      options: options ?? this.options,
      ybus: ybus != null ? ybus() : this.ybus,
      result: result != null ? result() : this.result,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      isCalculating: isCalculating ?? this.isCalculating,
    );
  }
}

/// Riverpod Notifier managing system configuration and solution calculation.
class PowerFlowNotifier extends Notifier<PowerFlowState> {
  @override
  PowerFlowState build() {
    return _create3BusPreset();
  }

  /// Preset 1: Standard EE4530 3-Bus Educational Network (H. Saadat benchmark)
  PowerFlowState _create3BusPreset() {
    final buses = [
      const BusModel(
        id: 'bus_1',
        busNumber: 1,
        name: 'Bus 1 (Slack)',
        type: BusType.slack,
        vMag: 1.05,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.0,
        qLoad: 0.0,
      ),
      const BusModel(
        id: 'bus_2',
        busNumber: 2,
        name: 'Bus 2 (PV Gen)',
        type: BusType.pv,
        vMag: 1.04,
        angleDeg: 0.0,
        pGen: 0.50, // 50 MW
        qGen: 0.0,
        pLoad: 0.0,
        qLoad: 0.0,
        qMin: -0.50,
        qMax: 1.00,
      ),
      const BusModel(
        id: 'bus_3',
        busNumber: 3,
        name: 'Bus 3 (PQ Load)',
        type: BusType.pq,
        vMag: 1.00,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 1.00, // 100 MW
        qLoad: 0.50, // 50 MVAr
      ),
    ];

    final lines = [
      const LineModel(
        id: 'line_1_2',
        fromBus: 1,
        toBus: 2,
        r: 0.02,
        x: 0.04,
        bHalf: 0.015,
        tap: 1.0,
      ),
      const LineModel(
        id: 'line_1_3',
        fromBus: 1,
        toBus: 3,
        r: 0.01,
        x: 0.03,
        bHalf: 0.01,
        tap: 1.0,
      ),
      const LineModel(
        id: 'line_2_3',
        fromBus: 2,
        toBus: 3,
        r: 0.0125,
        x: 0.025,
        bHalf: 0.01,
        tap: 1.0,
      ),
    ];

    return PowerFlowState(
      buses: buses,
      lines: lines,
      selectedMethod: PowerFlowMethod.newtonRaphson,
      options: const SolverOptions(
        tolerance: 1e-4,
        maxIterations: 50,
        enforceQLimits: true,
        accelerationFactor: 1.0,
      ),
    );
  }

  /// Preset 2: 2-Bus Generator to Load System (ideal for fundamental hand calculation verification)
  void load2BusPreset() {
    final buses = [
      const BusModel(
        id: 'bus_1',
        busNumber: 1,
        name: 'Bus 1 (Slack)',
        type: BusType.slack,
        vMag: 1.00,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.0,
        qLoad: 0.0,
      ),
      const BusModel(
        id: 'bus_2',
        busNumber: 2,
        name: 'Bus 2 (Load)',
        type: BusType.pq,
        vMag: 1.00,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.80,
        qLoad: 0.40,
      ),
    ];

    final lines = [
      const LineModel(
        id: 'line_1_2',
        fromBus: 1,
        toBus: 2,
        r: 0.05,
        x: 0.20,
        bHalf: 0.02,
        tap: 1.0,
      ),
    ];

    state = PowerFlowState(
      buses: buses,
      lines: lines,
      selectedMethod: state.selectedMethod,
      options: state.options,
    );
  }

  void load3BusPreset() {
    state = _create3BusPreset().copyWith(
      selectedMethod: state.selectedMethod,
      options: state.options,
    );
  }

  /// Preset 3: IEEE 14-Bus Benchmark System (Standard test case)
  void load14BusPreset() {
    final buses = [
      const BusModel(
        id: 'bus_1',
        busNumber: 1,
        name: 'Bus 1 (Slack)',
        type: BusType.slack,
        vMag: 1.060,
        angleDeg: 0.0,
      ),
      const BusModel(
        id: 'bus_2',
        busNumber: 2,
        name: 'Bus 2 (PV Gen)',
        type: BusType.pv,
        vMag: 1.045,
        angleDeg: 0.0,
        pGen: 0.40,
        qGen: 0.0,
        pLoad: 0.217,
        qLoad: 0.127,
        qMin: -0.40,
        qMax: 0.50,
      ),
      const BusModel(
        id: 'bus_3',
        busNumber: 3,
        name: 'Bus 3 (PV Gen)',
        type: BusType.pv,
        vMag: 1.010,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.942,
        qLoad: 0.190,
        qMin: 0.0,
        qMax: 0.40,
      ),
      const BusModel(
        id: 'bus_4',
        busNumber: 4,
        name: 'Bus 4 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.478,
        qLoad: -0.039,
      ),
      const BusModel(
        id: 'bus_5',
        busNumber: 5,
        name: 'Bus 5 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.076,
        qLoad: 0.016,
      ),
      const BusModel(
        id: 'bus_6',
        busNumber: 6,
        name: 'Bus 6 (PV Gen)',
        type: BusType.pv,
        vMag: 1.070,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.112,
        qLoad: 0.075,
        qMin: -0.06,
        qMax: 0.24,
      ),
      const BusModel(
        id: 'bus_7',
        busNumber: 7,
        name: 'Bus 7 (PQ)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.0,
        qLoad: 0.0,
      ),
      const BusModel(
        id: 'bus_8',
        busNumber: 8,
        name: 'Bus 8 (PV Gen)',
        type: BusType.pv,
        vMag: 1.090,
        angleDeg: 0.0,
        pGen: 0.0,
        qGen: 0.0,
        pLoad: 0.0,
        qLoad: 0.0,
        qMin: -0.06,
        qMax: 0.24,
      ),
      const BusModel(
        id: 'bus_9',
        busNumber: 9,
        name: 'Bus 9 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.295,
        qLoad: 0.166,
      ),
      const BusModel(
        id: 'bus_10',
        busNumber: 10,
        name: 'Bus 10 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.090,
        qLoad: 0.058,
      ),
      const BusModel(
        id: 'bus_11',
        busNumber: 11,
        name: 'Bus 11 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.035,
        qLoad: 0.018,
      ),
      const BusModel(
        id: 'bus_12',
        busNumber: 12,
        name: 'Bus 12 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.061,
        qLoad: 0.016,
      ),
      const BusModel(
        id: 'bus_13',
        busNumber: 13,
        name: 'Bus 13 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.135,
        qLoad: 0.058,
      ),
      const BusModel(
        id: 'bus_14',
        busNumber: 14,
        name: 'Bus 14 (PQ Load)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.149,
        qLoad: 0.050,
      ),
    ];

    final lines = [
      const LineModel(id: 'l_1_2', fromBus: 1, toBus: 2, r: 0.01938, x: 0.05917, bHalf: 0.0264),
      const LineModel(id: 'l_1_5', fromBus: 1, toBus: 5, r: 0.05403, x: 0.22304, bHalf: 0.0246),
      const LineModel(id: 'l_2_3', fromBus: 2, toBus: 3, r: 0.04699, x: 0.19797, bHalf: 0.0219),
      const LineModel(id: 'l_2_4', fromBus: 2, toBus: 4, r: 0.05811, x: 0.17632, bHalf: 0.0187),
      const LineModel(id: 'l_2_5', fromBus: 2, toBus: 5, r: 0.05695, x: 0.17388, bHalf: 0.0170),
      const LineModel(id: 'l_3_4', fromBus: 3, toBus: 4, r: 0.06701, x: 0.17103, bHalf: 0.0173),
      const LineModel(id: 'l_4_5', fromBus: 4, toBus: 5, r: 0.01335, x: 0.04211, bHalf: 0.0),
      const LineModel(id: 'l_4_7', fromBus: 4, toBus: 7, r: 0.0, x: 0.20912, bHalf: 0.0, tap: 0.978),
      const LineModel(id: 'l_4_9', fromBus: 4, toBus: 9, r: 0.0, x: 0.55618, bHalf: 0.0, tap: 0.969),
      const LineModel(id: 'l_5_6', fromBus: 5, toBus: 6, r: 0.0, x: 0.25202, bHalf: 0.0, tap: 0.932),
      const LineModel(id: 'l_6_11', fromBus: 6, toBus: 11, r: 0.09498, x: 0.19890, bHalf: 0.0),
      const LineModel(id: 'l_6_12', fromBus: 6, toBus: 12, r: 0.12291, x: 0.25581, bHalf: 0.0),
      const LineModel(id: 'l_6_13', fromBus: 6, toBus: 13, r: 0.06615, x: 0.13027, bHalf: 0.0),
      const LineModel(id: 'l_7_8', fromBus: 7, toBus: 8, r: 0.0, x: 0.17615, bHalf: 0.0),
      const LineModel(id: 'l_7_9', fromBus: 7, toBus: 9, r: 0.0, x: 0.11001, bHalf: 0.0),
      const LineModel(id: 'l_9_10', fromBus: 9, toBus: 10, r: 0.03181, x: 0.08450, bHalf: 0.0),
      const LineModel(id: 'l_9_14', fromBus: 9, toBus: 14, r: 0.12711, x: 0.27038, bHalf: 0.0),
      const LineModel(id: 'l_10_11', fromBus: 10, toBus: 11, r: 0.08205, x: 0.19207, bHalf: 0.0),
      const LineModel(id: 'l_12_13', fromBus: 12, toBus: 13, r: 0.22092, x: 0.19988, bHalf: 0.0),
      const LineModel(id: 'l_13_14', fromBus: 13, toBus: 14, r: 0.17093, x: 0.34802, bHalf: 0.0),
    ];

    state = PowerFlowState(
      buses: buses,
      lines: lines,
      selectedMethod: state.selectedMethod,
      options: state.options,
    );
  }

  void setMethod(PowerFlowMethod method) {
    state = state.copyWith(selectedMethod: method);
  }

  void updateOptions(SolverOptions options) {
    state = state.copyWith(options: options);
  }

  void addBus() {
    final nextNum = state.buses.isEmpty
        ? 1
        : state.buses.map((b) => b.busNumber).reduce((a, b) => a > b ? a : b) + 1;
    final newBus = BusModel(
      id: 'bus_$nextNum',
      busNumber: nextNum,
      name: 'Bus $nextNum (PQ)',
      type: BusType.pq,
      vMag: 1.0,
      angleDeg: 0.0,
      pGen: 0.0,
      qGen: 0.0,
      pLoad: 0.0,
      qLoad: 0.0,
    );
    state = state.copyWith(
      buses: [...state.buses, newBus],
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void updateBus(int index, BusModel updated) {
    final updatedList = List<BusModel>.from(state.buses);
    updatedList[index] = updated;
    state = state.copyWith(
      buses: updatedList,
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void removeBus(int index) {
    if (index < 0 || index >= state.buses.length) return;
    final busToRemove = state.buses[index];
    final updatedBuses = List<BusModel>.from(state.buses)..removeAt(index);
    // Remove lines referencing this bus
    final updatedLines = state.lines
        .where((l) => l.fromBus != busToRemove.busNumber && l.toBus != busToRemove.busNumber)
        .toList();

    state = state.copyWith(
      buses: updatedBuses,
      lines: updatedLines,
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void addLine() {
    if (state.buses.length < 2) return;
    final from = state.buses[0].busNumber;
    final to = state.buses[1].busNumber;
    final newLine = LineModel(
      id: 'line_${DateTime.now().millisecondsSinceEpoch}',
      fromBus: from,
      toBus: to,
      r: 0.02,
      x: 0.05,
      bHalf: 0.0,
      tap: 1.0,
    );
    state = state.copyWith(
      lines: [...state.lines, newLine],
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void updateLine(int index, LineModel updated) {
    final updatedList = List<LineModel>.from(state.lines);
    updatedList[index] = updated;
    state = state.copyWith(
      lines: updatedList,
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void removeLine(int index) {
    final updatedLines = List<LineModel>.from(state.lines)..removeAt(index);
    state = state.copyWith(
      lines: updatedLines,
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void addCustomBus(BusModel bus) {
    state = state.copyWith(
      buses: [...state.buses, bus],
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void updateBusByNumber(int busNumber, BusModel updated) {
    final idx = state.buses.indexWhere((b) => b.busNumber == busNumber);
    if (idx != -1) {
      updateBus(idx, updated);
    }
  }

  void removeBusByNumber(int busNumber) {
    final idx = state.buses.indexWhere((b) => b.busNumber == busNumber);
    if (idx != -1) {
      removeBus(idx);
    }
  }

  void addCustomLine(LineModel line) {
    state = state.copyWith(
      lines: [...state.lines, line],
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  void updateLineById(String lineId, LineModel updated) {
    final idx = state.lines.indexWhere((l) => l.id == lineId);
    if (idx != -1) {
      updateLine(idx, updated);
    }
  }

  void removeLineById(String lineId) {
    final idx = state.lines.indexWhere((l) => l.id == lineId);
    if (idx != -1) {
      removeLine(idx);
    }
  }

  void loadSandboxPreset({List<BusModel>? customBuses, List<LineModel>? customLines}) {
    state = state.copyWith(
      buses: customBuses ?? <BusModel>[],
      lines: customLines ?? <LineModel>[],
      result: () => null,
      ybus: () => null,
      errorMessage: () => null,
    );
  }

  /// Execute Y-bus building and Power Flow solution
  void calculate() {
    state = state.copyWith(
      isCalculating: true,
      errorMessage: () => null,
    );

    try {
      final busList = state.buses;
      final lineList = state.lines;

      if (busList.length < 2) {
        throw const PowerFlowException('Network must have at least 2 buses.');
      }

      final slacks = busList.where((b) => b.type == BusType.slack).toList();
      if (slacks.length != 1) {
        throw PowerFlowException(
          'Network must have exactly 1 Slack bus (found ${slacks.length}).',
        );
      }

      // Create mapping from 1-based busNumber to 0-based index
      final busMap = <int, int>{};
      for (var i = 0; i < busList.length; i++) {
        busMap[busList[i].busNumber] = i;
      }

      // Convert lines to BranchParams
      final branchParams = <BranchParams>[];
      for (final line in lineList) {
        branchParams.add(line.toBranchParams(busMap));
      }

      // Build Y-bus
      final ybus = YBusBuilder.build(busList.length, branchParams);

      // Convert buses to PfBus
      final pfBuses = busList.map((b) => b.toPfBus()).toList();

      // Solve according to selected method
      final PowerFlowResult result;
      if (state.selectedMethod == PowerFlowMethod.newtonRaphson) {
        final solver = NewtonRaphsonSolver(options: state.options);
        result = solver.solve(
          ybus: ybus,
          buses: pfBuses,
          branches: branchParams,
        );
      } else {
        final solver = GaussSeidelSolver(options: state.options);
        result = solver.solve(
          ybus: ybus,
          buses: pfBuses,
          branches: branchParams,
        );
      }

      state = state.copyWith(
        isCalculating: false,
        ybus: () => ybus,
        result: () => result,
        errorMessage: () => null,
      );
    } catch (e) {
      state = state.copyWith(
        isCalculating: false,
        errorMessage: () => e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

/// Global provider for power flow state and interactions
final powerFlowProvider =
    NotifierProvider<PowerFlowNotifier, PowerFlowState>(PowerFlowNotifier.new);
