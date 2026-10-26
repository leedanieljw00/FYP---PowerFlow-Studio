/// Model representing a generating unit participating in frequency control (governor droop).
class LfcGenerator {
  const LfcGenerator({
    required this.id,
    required this.name,
    required this.mvaBase,
    required this.droopR,
    this.inertiaH = 5.0,
    this.governorTau = 0.08,
    this.turbineTau = 0.30,
    this.isActive = true,
  }) : assert(mvaBase > 0, 'mvaBase must be positive'),
       assert(droopR > 0, 'droopR must be positive');

  final String id;
  final String name;

  /// Generator rated MVA base (e.g. 500 MVA)
  final double mvaBase;

  /// Speed regulation droop R (pu on unit MVA base, e.g. 0.05 for 5%)
  final double droopR;

  /// Generator inertia constant H (seconds, MJ/MVA)
  final double inertiaH;

  /// Governor time constant tau_g (seconds)
  final double governorTau;

  /// Turbine time constant tau_T (seconds)
  final double turbineTau;

  final bool isActive;

  /// Converts unit droop R to a common system MVA base:
  /// R_sys = R_unit * (S_base,sys / S_base,unit)
  double droopOnSystemBase(double systemMvaBase) {
    return droopR * (systemMvaBase / mvaBase);
  }

  /// Governor frequency response gain 1 / R_sys (pu/pu)
  double governorGainOnSystemBase(double systemMvaBase) {
    final rSys = droopOnSystemBase(systemMvaBase);
    return 1.0 / rSys;
  }

  LfcGenerator copyWith({
    String? id,
    String? name,
    double? mvaBase,
    double? droopR,
    double? inertiaH,
    double? governorTau,
    double? turbineTau,
    bool? isActive,
  }) {
    return LfcGenerator(
      id: id ?? this.id,
      name: name ?? this.name,
      mvaBase: mvaBase ?? this.mvaBase,
      droopR: droopR ?? this.droopR,
      inertiaH: inertiaH ?? this.inertiaH,
      governorTau: governorTau ?? this.governorTau,
      turbineTau: turbineTau ?? this.turbineTau,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Control area model for Load Frequency Control (LFC).
class LfcArea {
  const LfcArea({
    required this.id,
    required this.name,
    this.systemMvaBase = 1000.0,
    this.nominalFreq = 50.0,
    this.dampingD = 0.8,
    this.generators = const [],
    this.frequencyBiasB,
    this.integralGainKi = 0.05,
  });

  final String id;
  final String name;

  /// Common system MVA base (e.g. 1000 MVA)
  final double systemMvaBase;

  /// Nominal power grid frequency (50 Hz or 60 Hz)
  final double nominalFreq;

  /// System load-damping constant D (pu on system base)
  final double dampingD;

  /// Generating units in this control area
  final List<LfcGenerator> generators;

  /// Area frequency bias B (pu/pu or pu/Hz). If null, defaults to composite beta.
  final double? frequencyBiasB;

  /// Secondary AGC integral control gain K_I
  final double integralGainKi;

  /// Area composite frequency response characteristic:
  /// beta_sys = D + sum(1 / R_i,sys)  (pu/pu)
  double get betaSys {
    double sumGov = 0.0;
    for (final g in generators) {
      if (g.isActive) {
        sumGov += g.governorGainOnSystemBase(systemMvaBase);
      }
    }
    return dampingD + sumGov;
  }

  /// Frequency bias B (pu/pu)
  double get effectiveB => frequencyBiasB ?? betaSys;

  /// Equivalent inertia constant H_eq (seconds) on system base
  double get equivalentH {
    double totalH = 0.0;
    double totalMva = 0.0;
    for (final g in generators) {
      if (g.isActive) {
        totalH += g.inertiaH * g.mvaBase;
        totalMva += g.mvaBase;
      }
    }
    return totalMva > 0 ? totalH / systemMvaBase : 5.0;
  }

  LfcArea copyWith({
    String? id,
    String? name,
    double? systemMvaBase,
    double? nominalFreq,
    double? dampingD,
    List<LfcGenerator>? generators,
    double? Function()? frequencyBiasB,
    double? integralGainKi,
  }) {
    return LfcArea(
      id: id ?? this.id,
      name: name ?? this.name,
      systemMvaBase: systemMvaBase ?? this.systemMvaBase,
      nominalFreq: nominalFreq ?? this.nominalFreq,
      dampingD: dampingD ?? this.dampingD,
      generators: generators ?? this.generators,
      frequencyBiasB: frequencyBiasB != null ? frequencyBiasB() : this.frequencyBiasB,
      integralGainKi: integralGainKi ?? this.integralGainKi,
    );
  }
}
