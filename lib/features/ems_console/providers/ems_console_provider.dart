import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../economic_dispatch/providers/economic_dispatch_provider.dart';
import '../../load_frequency_control/providers/lfc_provider.dart';
import '../../power_flow/providers/power_flow_provider.dart';
import '../models/dynamic_lfc_params.dart';

enum AceSeverity {
  normal('Normal Operations', 'Grid balanced within standard regulation limits'),
  warning('Advisory / Warning', 'Area Control Error exceeds primary deadband'),
  emergency('Emergency Alert', 'Urgent regulation required to prevent frequency excursions');

  const AceSeverity(this.title, this.description);
  final String title;
  final String description;
}

class EmsConsoleState {
  const EmsConsoleState({
    required this.totalGenMW,
    required this.totalGenMvar,
    required this.totalLoadMW,
    required this.totalLoadMvar,
    required this.totalLossMW,
    required this.totalLossMvar,
    required this.systemLambda,
    required this.gridFrequencyHz,
    required this.deltaFreqHz,
    required this.aceMW,
    required this.deltaPtieMW,
    required this.freqBiasMW,
    required this.aceSeverity,
    required this.dynamicParams,
    this.mvaBase = 100.0,
  });

  final double totalGenMW;
  final double totalGenMvar;
  final double totalLoadMW;
  final double totalLoadMvar;
  final double totalLossMW;
  final double totalLossMvar;
  final double systemLambda;
  final double gridFrequencyHz;
  final double deltaFreqHz;
  final double aceMW;
  final double deltaPtieMW;
  final double freqBiasMW;
  final AceSeverity aceSeverity;
  final DynamicLfcParams dynamicParams;
  final double mvaBase;

  EmsConsoleState copyWith({
    double? totalGenMW,
    double? totalGenMvar,
    double? totalLoadMW,
    double? totalLoadMvar,
    double? totalLossMW,
    double? totalLossMvar,
    double? systemLambda,
    double? gridFrequencyHz,
    double? deltaFreqHz,
    double? aceMW,
    double? deltaPtieMW,
    double? freqBiasMW,
    AceSeverity? aceSeverity,
    DynamicLfcParams? dynamicParams,
    double? mvaBase,
  }) {
    return EmsConsoleState(
      totalGenMW: totalGenMW ?? this.totalGenMW,
      totalGenMvar: totalGenMvar ?? this.totalGenMvar,
      totalLoadMW: totalLoadMW ?? this.totalLoadMW,
      totalLoadMvar: totalLoadMvar ?? this.totalLoadMvar,
      totalLossMW: totalLossMW ?? this.totalLossMW,
      totalLossMvar: totalLossMvar ?? this.totalLossMvar,
      systemLambda: systemLambda ?? this.systemLambda,
      gridFrequencyHz: gridFrequencyHz ?? this.gridFrequencyHz,
      deltaFreqHz: deltaFreqHz ?? this.deltaFreqHz,
      aceMW: aceMW ?? this.aceMW,
      deltaPtieMW: deltaPtieMW ?? this.deltaPtieMW,
      freqBiasMW: freqBiasMW ?? this.freqBiasMW,
      aceSeverity: aceSeverity ?? this.aceSeverity,
      dynamicParams: dynamicParams ?? this.dynamicParams,
      mvaBase: mvaBase ?? this.mvaBase,
    );
  }
}

class EmsConsoleNotifier extends Notifier<EmsConsoleState> {
  @override
  EmsConsoleState build() {
    final pfState = ref.watch(powerFlowProvider);
    final edState = ref.watch(economicDispatchProvider);
    final lfcState = ref.watch(lfcProvider);

    const mvaBase = 100.0;

    // 1. Power Flow Telemetry
    double genMW = 0.0;
    double genMvar = 0.0;
    double loadMW = 0.0;
    double loadMvar = 0.0;
    double lossMW = 0.0;
    double lossMvar = 0.0;

    final pfRes = pfState.result;
    if (pfRes != null) {
      genMW = pfRes.totalGeneration.re * mvaBase;
      genMvar = pfRes.totalGeneration.im * mvaBase;
      loadMW = pfRes.totalLoad.re * mvaBase;
      loadMvar = pfRes.totalLoad.im * mvaBase;
      lossMW = pfRes.totalLoss.re * mvaBase;
      lossMvar = pfRes.totalLoss.im * mvaBase;
    } else {
      // Aggregate scheduled input quantities if solver hasn't executed
      for (final b in pfState.buses) {
        genMW += b.pGen * mvaBase;
        genMvar += b.qGen * mvaBase;
        loadMW += b.pLoad * mvaBase;
        loadMvar += b.qLoad * mvaBase;
      }
    }

    // 2. Economic Dispatch Telemetry
    final lambda = edState.losslessResult?.lambda ??
        edState.lossResult?.lambda ??
        8.50;

    // 3. Frequency & Area Control Error (ACE)
    final f0 = lfcState.area1.nominalFreq;
    double deltaF_Hz = 0.0;
    double ace_MW = 0.0;
    double tie_MW = 0.0;
    double bias_MW = 0.0;

    if (lfcState.isTwoAreaMode && lfcState.twoAreaResult != null) {
      final res = lfcState.twoAreaResult!;
      deltaF_Hz = res.deltaF_Hz;
      ace_MW = res.ace1_MW;
      tie_MW = res.deltaPtie1_MW;
      bias_MW = res.b1 * res.deltaF_pu * lfcState.area1.systemMvaBase;
    } else if (lfcState.singleAreaResult != null) {
      final res = lfcState.singleAreaResult!;
      deltaF_Hz = res.deltaF_Hz;
      // In single area, ACE = B * delta_f
      final bSys = lfcState.area1.effectiveB;
      bias_MW = bSys * res.deltaF_pu * lfcState.area1.systemMvaBase;
      ace_MW = bias_MW;
    }

    final double gridFreqHz = f0 + deltaF_Hz;

    // Severity assessment: Normal <= 5 MW, Warning <= 20 MW, Emergency > 20 MW
    final absAce = ace_MW.abs();
    final AceSeverity severity;
    if (absAce <= 5.0) {
      severity = AceSeverity.normal;
    } else if (absAce <= 20.0) {
      severity = AceSeverity.warning;
    } else {
      severity = AceSeverity.emergency;
    }

    // Build dynamic LFC simulation parameters based on active area
    final dynamicParams = DynamicLfcParams(
      inertiaH: lfcState.area1.equivalentH,
      dampingD: lfcState.area1.dampingD,
      droopR: lfcState.area1.generators.isNotEmpty
          ? lfcState.area1.generators.first.droopR
          : 0.05,
      integralGainKi: lfcState.area1.integralGainKi,
      stepLoadDeltaPL_MW: lfcState.deltaPL1_MW,
      systemMvaBase: lfcState.area1.systemMvaBase,
      nominalFreq: f0,
    );

    return EmsConsoleState(
      totalGenMW: genMW,
      totalGenMvar: genMvar,
      totalLoadMW: loadMW,
      totalLoadMvar: loadMvar,
      totalLossMW: lossMW,
      totalLossMvar: lossMvar,
      systemLambda: lambda,
      gridFrequencyHz: gridFreqHz,
      deltaFreqHz: deltaF_Hz,
      aceMW: ace_MW,
      deltaPtieMW: tie_MW,
      freqBiasMW: bias_MW,
      aceSeverity: severity,
      dynamicParams: dynamicParams,
      mvaBase: mvaBase,
    );
  }

  void updateDynamicParams(DynamicLfcParams params) {
    state = state.copyWith(dynamicParams: params);
  }
}

final emsConsoleProvider =
    NotifierProvider<EmsConsoleNotifier, EmsConsoleState>(
  EmsConsoleNotifier.new,
);
