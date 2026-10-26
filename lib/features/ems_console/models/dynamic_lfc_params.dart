/// Parameter configuration for dynamic load-frequency transient simulation.
class DynamicLfcParams {
  const DynamicLfcParams({
    this.inertiaH = 5.0,
    this.dampingD = 0.8,
    this.droopR = 0.05,
    this.governorTau = 0.08,
    this.turbineTau = 0.30,
    this.integralGainKi = 0.4,
    this.stepLoadDeltaPL_MW = 50.0,
    this.systemMvaBase = 1000.0,
    this.nominalFreq = 50.0,
    this.tMax = 30.0,
    this.dt = 0.02,
  }) : assert(inertiaH > 0, 'Inertia constant H must be positive'),
       assert(droopR > 0, 'Governor droop R must be positive'),
       assert(governorTau > 0, 'Governor time constant must be positive'),
       assert(turbineTau > 0, 'Turbine time constant must be positive');

  /// Equivalent inertia constant H (seconds, MJ/MVA)
  final double inertiaH;

  /// Load-damping coefficient D (pu/pu)
  final double dampingD;

  /// Equivalent governor speed regulation droop R (pu/pu)
  final double droopR;

  /// Speed governor time constant tau_g (seconds)
  final double governorTau;

  /// Steam/hydraulic turbine time constant tau_T (seconds)
  final double turbineTau;

  /// Secondary AGC integral control gain K_I
  final double integralGainKi;

  /// Magnitude of step load disturbance (MW)
  final double stepLoadDeltaPL_MW;

  /// System rated MVA base (e.g. 1000 MVA)
  final double systemMvaBase;

  /// Grid nominal operating frequency (50 Hz or 60 Hz)
  final double nominalFreq;

  /// Maximum simulation time window (seconds, [0, 30s])
  final double tMax;

  /// Numerical integration step size dt (seconds)
  final double dt;

  /// Step load in per unit on system base
  double get deltaPL_pu => stepLoadDeltaPL_MW / systemMvaBase;

  /// Composite frequency response characteristic beta = D + 1/R (pu/pu)
  double get beta => dampingD + (1.0 / droopR);

  /// Theoretical steady-state frequency deviation for primary droop only (pu)
  double get steadyStateDeltaF_pu => beta > 0 ? -deltaPL_pu / beta : 0.0;

  /// Theoretical steady-state frequency deviation for primary droop only (Hz)
  double get steadyStateDeltaF_Hz => steadyStateDeltaF_pu * nominalFreq;

  /// Theoretical steady-state frequency for primary droop only (Hz)
  double get steadyStateFreq_Hz => nominalFreq + steadyStateDeltaF_Hz;

  DynamicLfcParams copyWith({
    double? inertiaH,
    double? dampingD,
    double? droopR,
    double? governorTau,
    double? turbineTau,
    double? integralGainKi,
    double? stepLoadDeltaPL_MW,
    double? systemMvaBase,
    double? nominalFreq,
    double? tMax,
    double? dt,
  }) {
    return DynamicLfcParams(
      inertiaH: inertiaH ?? this.inertiaH,
      dampingD: dampingD ?? this.dampingD,
      droopR: droopR ?? this.droopR,
      governorTau: governorTau ?? this.governorTau,
      turbineTau: turbineTau ?? this.turbineTau,
      integralGainKi: integralGainKi ?? this.integralGainKi,
      stepLoadDeltaPL_MW: stepLoadDeltaPL_MW ?? this.stepLoadDeltaPL_MW,
      systemMvaBase: systemMvaBase ?? this.systemMvaBase,
      nominalFreq: nominalFreq ?? this.nominalFreq,
      tMax: tMax ?? this.tMax,
      dt: dt ?? this.dt,
    );
  }
}

/// A single snapshot point along the time-domain dynamic LFC response trajectory.
class DynamicLfcTrajectoryPoint {
  const DynamicLfcTrajectoryPoint({
    required this.time,
    required this.deltaF_pu,
    required this.deltaF_Hz,
    required this.frequency_Hz,
    required this.deltaPm_MW,
    required this.deltaPv_MW,
    required this.deltaPref_MW,
  });

  /// Time instant in seconds (t in [0, tMax])
  final double time;

  /// Frequency deviation in per unit
  final double deltaF_pu;

  /// Frequency deviation in Hertz
  final double deltaF_Hz;

  /// Instantaneous frequency f(t) = f_0 + delta_f(t) (Hz)
  final double frequency_Hz;

  /// Mechanical turbine power response in MW
  final double deltaPm_MW;

  /// Governor valve position deviation in MW
  final double deltaPv_MW;

  /// Secondary AGC reference power deviation in MW
  final double deltaPref_MW;
}
