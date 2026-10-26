import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/load_frequency_control/droop_solver.dart';
import '../../../core/math/load_frequency_control/lfc_models.dart';
import '../../../core/math/load_frequency_control/two_area_lfc.dart';

class LfcState {
  const LfcState({
    required this.isTwoAreaMode,
    required this.area1,
    required this.area2,
    required this.deltaPL1_MW,
    required this.deltaPL2_MW,
    this.enableAGC = false,
    this.singleAreaResult,
    this.twoAreaResult,
    this.transientTrajectory = const [],
    this.errorMessage,
    this.isCalculating = false,
  });

  final bool isTwoAreaMode;
  final LfcArea area1;
  final LfcArea area2;
  final double deltaPL1_MW;
  final double deltaPL2_MW;
  final bool enableAGC;

  final SingleAreaDroopResult? singleAreaResult;
  final TwoAreaLfcResult? twoAreaResult;
  final List<LfcSimulationPoint> transientTrajectory;
  final String? errorMessage;
  final bool isCalculating;

  LfcState copyWith({
    bool? isTwoAreaMode,
    LfcArea? area1,
    LfcArea? area2,
    double? deltaPL1_MW,
    double? deltaPL2_MW,
    bool? enableAGC,
    SingleAreaDroopResult? Function()? singleAreaResult,
    TwoAreaLfcResult? Function()? twoAreaResult,
    List<LfcSimulationPoint>? transientTrajectory,
    String? Function()? errorMessage,
    bool? isCalculating,
  }) {
    return LfcState(
      isTwoAreaMode: isTwoAreaMode ?? this.isTwoAreaMode,
      area1: area1 ?? this.area1,
      area2: area2 ?? this.area2,
      deltaPL1_MW: deltaPL1_MW ?? this.deltaPL1_MW,
      deltaPL2_MW: deltaPL2_MW ?? this.deltaPL2_MW,
      enableAGC: enableAGC ?? this.enableAGC,
      singleAreaResult: singleAreaResult != null ? singleAreaResult() : this.singleAreaResult,
      twoAreaResult: twoAreaResult != null ? twoAreaResult() : this.twoAreaResult,
      transientTrajectory: transientTrajectory ?? this.transientTrajectory,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      isCalculating: isCalculating ?? this.isCalculating,
    );
  }
}

class LfcNotifier extends Notifier<LfcState> {
  @override
  LfcState build() {
    return _createEe4530ParallelDroopPreset();
  }

  /// Preset 1: EE4530 Example 2.3 & Tutorial 4 Q1
  /// Two parallel generators: R1 = 6% (0.06), R2 = 4% (0.04), ΔP_L = 90 MW.
  LfcState _createEe4530ParallelDroopPreset() {
    final area1 = LfcArea(
      id: 'area_1',
      name: 'System Area 1',
      systemMvaBase: 1000.0,
      nominalFreq: 50.0,
      dampingD: 0.0, // In Ex 2.3 / Tut 4 Q1, load damping D = 0 for pure droop verification
      generators: const [
        LfcGenerator(
          id: 'gen_1',
          name: 'Generator 1 (R=6%)',
          mvaBase: 1000.0,
          droopR: 0.06,
          inertiaH: 5.0,
          governorTau: 0.10,
          turbineTau: 0.35,
        ),
        LfcGenerator(
          id: 'gen_2',
          name: 'Generator 2 (R=4%)',
          mvaBase: 1000.0,
          droopR: 0.04,
          inertiaH: 4.5,
          governorTau: 0.08,
          turbineTau: 0.30,
        ),
      ],
      integralGainKi: 0.08,
    );

    final area2 = LfcArea(
      id: 'area_2',
      name: 'Interconnected Area 2',
      systemMvaBase: 1000.0,
      nominalFreq: 50.0,
      dampingD: 0.8,
      generators: const [
        LfcGenerator(
          id: 'gen_2_1',
          name: 'Area 2 Gen (R=5%)',
          mvaBase: 1000.0,
          droopR: 0.05,
          inertiaH: 5.0,
        ),
      ],
    );

    final state = LfcState(
      isTwoAreaMode: false,
      area1: area1,
      area2: area2,
      deltaPL1_MW: 90.0,
      deltaPL2_MW: 0.0,
      enableAGC: false,
    );

    final steady = DroopSolver.solveSteadyState(area: area1, deltaPL_MW: 90.0);
    final traj = DroopSolver.simulateTransient(area: area1, deltaPL_MW: 90.0, enableAGC: false);

    return state.copyWith(
      singleAreaResult: () => steady,
      transientTrajectory: traj,
    );
  }

  /// Preset 2: EE4530 Assignment 1 Q1 (Two-Area Interconnected Grid)
  void loadAssignment1TwoAreaPreset() {
    final area1 = LfcArea(
      id: 'area_1',
      name: 'Area 1 (B=12.5)',
      systemMvaBase: 1000.0,
      nominalFreq: 50.0,
      dampingD: 0.5,
      frequencyBiasB: 12.5,
      generators: const [
        LfcGenerator(
          id: 'g1',
          name: 'Area 1 Hydro/Thermal',
          mvaBase: 1000.0,
          droopR: 0.0833, // 1/R = 12.0
        ),
      ],
    );

    final area2 = LfcArea(
      id: 'area_2',
      name: 'Area 2 (B=25.0)',
      systemMvaBase: 1000.0,
      nominalFreq: 50.0,
      dampingD: 1.0,
      frequencyBiasB: 25.0,
      generators: const [
        LfcGenerator(
          id: 'g2',
          name: 'Area 2 Major Grid',
          mvaBase: 1000.0,
          droopR: 0.0416, // 1/R = 24.0
        ),
      ],
    );

    state = state.copyWith(
      isTwoAreaMode: true,
      area1: area1,
      area2: area2,
      deltaPL1_MW: 100.0,
      deltaPL2_MW: 0.0,
      enableAGC: false,
    );
    calculate();
  }

  void loadParallelDroopPreset() {
    state = _createEe4530ParallelDroopPreset();
    calculate();
  }

  void setTwoAreaMode(bool value) {
    state = state.copyWith(isTwoAreaMode: value);
    calculate();
  }

  void setLoadSurgeArea1(double mw) {
    state = state.copyWith(deltaPL1_MW: mw);
    calculate();
  }

  void setLoadSurgeArea2(double mw) {
    state = state.copyWith(deltaPL2_MW: mw);
    calculate();
  }

  void setEnableAGC(bool value) {
    state = state.copyWith(enableAGC: value);
    calculate();
  }

  void updateArea1(LfcArea area) {
    state = state.copyWith(area1: area);
    calculate();
  }

  void updateArea2(LfcArea area) {
    state = state.copyWith(area2: area);
    calculate();
  }

  void calculate() {
    state = state.copyWith(isCalculating: true, errorMessage: () => null);

    try {
      if (state.isTwoAreaMode) {
        final result = TwoAreaLfcSolver.solve(
          area1: state.area1,
          area2: state.area2,
          deltaPL1_MW: state.deltaPL1_MW,
          deltaPL2_MW: state.deltaPL2_MW,
        );

        // Also simulate dynamic trajectory for Area 1
        final traj = DroopSolver.simulateTransient(
          area: state.area1,
          deltaPL_MW: state.deltaPL1_MW,
          enableAGC: state.enableAGC,
        );

        state = state.copyWith(
          isCalculating: false,
          twoAreaResult: () => result,
          singleAreaResult: () => null,
          transientTrajectory: traj,
        );
      } else {
        final result = DroopSolver.solveSteadyState(
          area: state.area1,
          deltaPL_MW: state.deltaPL1_MW,
        );

        final traj = DroopSolver.simulateTransient(
          area: state.area1,
          deltaPL_MW: state.deltaPL1_MW,
          enableAGC: state.enableAGC,
        );

        state = state.copyWith(
          isCalculating: false,
          singleAreaResult: () => result,
          twoAreaResult: () => null,
          transientTrajectory: traj,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isCalculating: false,
        errorMessage: () => e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

final lfcProvider = NotifierProvider<LfcNotifier, LfcState>(LfcNotifier.new);
