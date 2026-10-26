import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/math/economic_dispatch/generator_model.dart';
import '../../../core/math/economic_dispatch/loss_dispatch.dart';
import '../../../core/math/economic_dispatch/lossless_dispatch.dart';

class EconomicDispatchState {
  const EconomicDispatchState({
    required this.units,
    required this.demand,
    this.includeLosses = false,
    this.enforceLimits = true,
    required this.lossCoeffs,
    this.losslessResult,
    this.lossResult,
    this.errorMessage,
    this.isCalculating = false,
  });

  final List<GeneratorUnit> units;
  final double demand; // MW
  final bool includeLosses;
  final bool enforceLimits;
  final LossCoefficients lossCoeffs;
  final LosslessDispatchResult? losslessResult;
  final LossDispatchResult? lossResult;
  final String? errorMessage;
  final bool isCalculating;

  EconomicDispatchState copyWith({
    List<GeneratorUnit>? units,
    double? demand,
    bool? includeLosses,
    bool? enforceLimits,
    LossCoefficients? lossCoeffs,
    LosslessDispatchResult? Function()? losslessResult,
    LossDispatchResult? Function()? lossResult,
    String? Function()? errorMessage,
    bool? isCalculating,
  }) {
    return EconomicDispatchState(
      units: units ?? this.units,
      demand: demand ?? this.demand,
      includeLosses: includeLosses ?? this.includeLosses,
      enforceLimits: enforceLimits ?? this.enforceLimits,
      lossCoeffs: lossCoeffs ?? this.lossCoeffs,
      losslessResult: losslessResult != null ? losslessResult() : this.losslessResult,
      lossResult: lossResult != null ? lossResult() : this.lossResult,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      isCalculating: isCalculating ?? this.isCalculating,
    );
  }
}

class EconomicDispatchNotifier extends Notifier<EconomicDispatchState> {
  @override
  EconomicDispatchState build() {
    return _createEe4530TwoUnitPreset();
  }

  /// Preset 1: EE4530 Example 2.6 & Tutorial 5 Q1 (2-Unit Classic)
  EconomicDispatchState _createEe4530TwoUnitPreset() {
    final units = [
      const GeneratorUnit(
        id: 'gen_1',
        name: 'Unit 1 (Base Load)',
        alpha: 100.0,
        beta: 8.0,
        gamma: 0.008,
        pMin: 100.0,
        pMax: 625.0,
      ),
      const GeneratorUnit(
        id: 'gen_2',
        name: 'Unit 2 (Mid Merit)',
        alpha: 120.0,
        beta: 6.4,
        gamma: 0.0096,
        pMin: 100.0,
        pMax: 625.0,
      ),
    ];

    final bMatrix = [
      [0.0001, 0.00001],
      [0.00001, 0.00015],
    ];

    final state = EconomicDispatchState(
      units: units,
      demand: 800.0,
      includeLosses: false,
      enforceLimits: true,
      lossCoeffs: LossCoefficients(bMatrix: bMatrix),
    );

    // Initial dispatch calculation
    final result = LosslessDispatchSolver.solve(
      units: units,
      demand: 800.0,
      enforceLimits: true,
    );

    return state.copyWith(losslessResult: () => result);
  }

  /// Preset 2: 3-Unit System with Transmission Loss B-matrix
  void load3UnitPreset() {
    final units = [
      const GeneratorUnit(
        id: 'gen_1',
        name: 'Unit 1 (Coal/Base)',
        alpha: 561.0,
        beta: 7.92,
        gamma: 0.001562,
        pMin: 100.0,
        pMax: 600.0,
      ),
      const GeneratorUnit(
        id: 'gen_2',
        name: 'Unit 2 (CCGT)',
        alpha: 310.0,
        beta: 7.85,
        gamma: 0.00194,
        pMin: 100.0,
        pMax: 400.0,
      ),
      const GeneratorUnit(
        id: 'gen_3',
        name: 'Unit 3 (Peaker)',
        alpha: 78.0,
        beta: 7.97,
        gamma: 0.00482,
        pMin: 50.0,
        pMax: 200.0,
      ),
    ];

    final bMatrix = [
      [0.000075, 0.000005, 0.0000075],
      [0.000005, 0.000015, 0.000010],
      [0.0000075, 0.000010, 0.000045],
    ];

    state = EconomicDispatchState(
      units: units,
      demand: 850.0,
      includeLosses: false,
      enforceLimits: true,
      lossCoeffs: LossCoefficients(bMatrix: bMatrix),
    );
    calculate();
  }

  void loadEe4530Preset() {
    state = _createEe4530TwoUnitPreset();
    calculate();
  }

  void setDemand(double demand) {
    state = state.copyWith(demand: demand);
    calculate();
  }

  void setIncludeLosses(bool include) {
    state = state.copyWith(includeLosses: include);
    calculate();
  }

  void setEnforceLimits(bool enforce) {
    state = state.copyWith(enforceLimits: enforce);
    calculate();
  }

  void addUnit() {
    final nextNum = state.units.length + 1;
    final newUnit = GeneratorUnit(
      id: 'gen_$nextNum',
      name: 'Unit $nextNum',
      alpha: 150.0,
      beta: 7.5,
      gamma: 0.008,
      pMin: 50.0,
      pMax: 500.0,
    );
    final updated = [...state.units, newUnit];
    final n = updated.length;
    final newB = List.generate(n, (i) => List.generate(n, (j) => i == j ? 0.0001 : 0.00001));

    state = state.copyWith(
      units: updated,
      lossCoeffs: LossCoefficients(bMatrix: newB),
    );
    calculate();
  }

  void updateUnit(int index, GeneratorUnit updated) {
    final updatedList = List<GeneratorUnit>.from(state.units);
    updatedList[index] = updated;
    state = state.copyWith(units: updatedList);
    calculate();
  }

  void removeUnit(int index) {
    if (state.units.length <= 2) {
      state = state.copyWith(
        errorMessage: () => 'At least two generating units are required.',
      );
      return;
    }
    final updatedList = List<GeneratorUnit>.from(state.units)..removeAt(index);
    final n = updatedList.length;
    final newB = List.generate(n, (i) => List.generate(n, (j) => i == j ? 0.0001 : 0.00001));

    state = state.copyWith(
      units: updatedList,
      lossCoeffs: LossCoefficients(bMatrix: newB),
    );
    calculate();
  }

  void calculate() {
    state = state.copyWith(isCalculating: true, errorMessage: () => null);

    try {
      if (state.includeLosses) {
        final result = LossDispatchSolver.solve(
          units: state.units,
          demand: state.demand,
          lossCoeffs: state.lossCoeffs,
        );
        state = state.copyWith(
          isCalculating: false,
          lossResult: () => result,
          losslessResult: () => null,
          errorMessage: () => result.converged ? null : result.message,
        );
      } else {
        final result = LosslessDispatchSolver.solve(
          units: state.units,
          demand: state.demand,
          enforceLimits: state.enforceLimits,
        );
        state = state.copyWith(
          isCalculating: false,
          losslessResult: () => result,
          lossResult: () => null,
          errorMessage: () => result.isFeasible ? null : result.message,
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

final economicDispatchProvider =
    NotifierProvider<EconomicDispatchNotifier, EconomicDispatchState>(
  EconomicDispatchNotifier.new,
);
