import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:powerflow_studio/core/math/complex.dart';
import 'package:powerflow_studio/core/math/power_flow_common.dart';
import 'package:powerflow_studio/features/ems_console/engine/lfc_transient_engine.dart';
import 'package:powerflow_studio/features/ems_console/models/dynamic_lfc_params.dart';
import 'package:powerflow_studio/features/ems_console/providers/ems_console_provider.dart';
import 'package:powerflow_studio/features/ems_console/views/widgets/frequency_transient_chart.dart';
import 'package:powerflow_studio/features/power_flow/providers/power_flow_provider.dart';
import 'package:powerflow_studio/features/sld_workspace/models/sld_bus_node.dart';
import 'package:powerflow_studio/features/sld_workspace/models/sld_line_branch.dart';
import 'package:powerflow_studio/features/sld_workspace/providers/sld_workspace_provider.dart';
import 'package:powerflow_studio/features/sld_workspace/views/widgets/bus_inspector_sheet.dart';
import 'package:powerflow_studio/features/sld_workspace/views/widgets/connect_buses_dialog.dart';
import 'package:powerflow_studio/features/sld_workspace/views/widgets/custom_bus_dialog.dart';

void main() {
  group('Phase 3 SLD Canvas Models & Interaction', () {
    test('SldBusNode electrical quantities and hit-testing', () {
      final bus = SldBusNode(
        busNumber: 1,
        name: 'Bus 1 (Slack)',
        type: BusType.slack,
        position: const Offset(300, 300),
        isVertical: false,
        length: 80,
        vMag: 1.05,
        angleDeg: 0.0,
        pGen: 1.2,
        qGen: 0.4,
        pLoad: 0.5,
        qLoad: 0.2,
      );

      expect(bus.pNet, closeTo(0.7, 1e-6));
      expect(bus.qNet, closeTo(0.2, 1e-6));
      expect(bus.hasGenerator, isTrue);
      expect(bus.hasLoad, isTrue);
      expect(bus.startPoint, const Offset(260, 300));
      expect(bus.endPoint, const Offset(340, 300));

      // Test tap on bus center
      expect(bus.hitTest(const Offset(300, 300)), isTrue);
      // Test tap on bus endpoint
      expect(bus.hitTest(const Offset(335, 305)), isTrue);
      // Test tap far away
      expect(bus.hitTest(const Offset(500, 500)), isFalse);
    });

    test('SldLineBranch electrical parameters and segment hit-testing', () {
      final line = SldLineBranch(
        id: 'l_1_2',
        fromBus: 1,
        toBus: 2,
        r: 0.02,
        x: 0.06,
        bHalf: 0.015,
        tap: 1.0,
        sFromTo: const Complex(0.45, 0.15),
        sToFrom: const Complex(-0.43, -0.13),
      );

      expect(line.pFromTo, closeTo(0.45, 1e-6));
      expect(line.qFromTo, closeTo(0.15, 1e-6));
      expect(line.pLoss, closeTo(0.02, 1e-6)); // 0.45 - 0.43 = 0.02 pu loss
      expect(line.qLoss, closeTo(0.02, 1e-6));
      expect(line.isTransformer, isFalse);

      // Hit testing along branch segment from (100, 100) to (500, 100)
      const fromPos = Offset(100, 100);
      const toPos = Offset(500, 100);

      // Near midpoint
      expect(line.hitTest(const Offset(300, 105), fromPos, toPos), isTrue);
      // Far from segment
      expect(line.hitTest(const Offset(300, 200), fromPos, toPos), isFalse);
    });

    test('SldWorkspaceNotifier preset loading and synchronization', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial state is 3-Bus Saadat
      var state = container.read(sldWorkspaceProvider);
      expect(state.currentPreset, equals(PresetTopology.threeBus));
      expect(state.buses.length, equals(3));
      expect(state.lines.length, equals(3));

      final notifier = container.read(sldWorkspaceProvider.notifier);

      // Load 2-Bus preset
      notifier.loadPreset(PresetTopology.twoBus);
      state = container.read(sldWorkspaceProvider);
      expect(state.currentPreset, equals(PresetTopology.twoBus));
      expect(state.buses.length, equals(2));
      expect(state.lines.length, equals(1));

      // Load IEEE 14-Bus benchmark preset
      notifier.loadPreset(PresetTopology.ieee14Bus);
      state = container.read(sldWorkspaceProvider);
      expect(state.currentPreset, equals(PresetTopology.ieee14Bus));
      expect(state.buses.length, equals(14));
      expect(state.lines.length, equals(20));

      // Select bus & line
      notifier.selectBus(2);
      expect(container.read(sldWorkspaceProvider).selectedBusNumber, equals(2));
      notifier.selectLine('l_1_2');
      expect(container.read(sldWorkspaceProvider).selectedLineId, equals('l_1_2'));
      expect(container.read(sldWorkspaceProvider).selectedBusNumber, isNull);

      notifier.clearSelection();
      expect(container.read(sldWorkspaceProvider).selectedLineId, isNull);
    });

    test('SldWorkspaceNotifier: sandbox mode starts blank, custom buses, connections, movement, solve, and removal', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(sldWorkspaceProvider.notifier);

      // 1. Switch to Sandbox Preset: should be completely blank
      notifier.loadPreset(PresetTopology.sandbox);
      var state = container.read(sldWorkspaceProvider);
      expect(state.currentPreset, equals(PresetTopology.sandbox));
      expect(state.buses.isEmpty, isTrue);
      expect(state.lines.isEmpty, isTrue);

      // 2. Add Bus 1 (Slack Generator)
      notifier.addCustomBus(
        position: const Offset(320, 300),
        name: 'Bus 1 (Main Grid Slack)',
        type: BusType.slack,
        vMag: 1.05,
        angleDeg: 0.0,
        pGen: 1.0,
        qGen: 0.2,
      );
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.length, equals(1));
      expect(state.buses.first.busNumber, equals(1));
      expect(state.buses.first.type, equals(BusType.slack));

      // 3. Add Bus 2 (PQ Load)
      notifier.addCustomBus(
        position: const Offset(700, 300),
        name: 'Bus 2 (City Substation)',
        type: BusType.pq,
        vMag: 1.0,
        angleDeg: 0.0,
        pLoad: 0.60,
        qLoad: 0.25,
      );
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.length, equals(2));

      // 4. Connect Bus 1 and Bus 2 with a branch
      notifier.connectBuses(
        fromBus: 1,
        toBus: 2,
        r: 0.02,
        x: 0.08,
        bHalf: 0.01,
      );
      state = container.read(sldWorkspaceProvider);
      expect(state.lines.length, equals(1));
      expect(state.lines.first.fromBus, equals(1));
      expect(state.lines.first.toBus, equals(2));

      // 5. Add custom Bus 3 (PV Solar Farm + Industrial Load)
      notifier.addCustomBus(
        position: const Offset(500, 500),
        name: 'Bus 3 (Solar & Factory)',
        type: BusType.pv,
        vMag: 1.02,
        angleDeg: 0.0,
        pGen: 0.60,
        qGen: 0.15,
        pLoad: 0.25,
        qLoad: 0.10,
        qMin: -0.30,
        qMax: 0.80,
        isVertical: false,
      );
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.length, equals(3));

      final bus3 = state.buses.firstWhere((b) => b.busNumber == 3);
      expect(bus3.name, equals('Bus 3 (Solar & Factory)'));
      expect(bus3.type, equals(BusType.pv));
      expect(bus3.hasGenerator, isTrue);
      expect(bus3.hasLoad, isTrue);
      expect(bus3.pGen, closeTo(0.60, 1e-4));
      expect(bus3.pLoad, closeTo(0.25, 1e-4));
      expect(bus3.pNet, closeTo(0.35, 1e-4)); // Net export 0.60 - 0.25 = 0.35 pu

      // 6. Connect Bus 2 to Bus 3 and Bus 1 to Bus 3 (forming a 3-bus loop)
      notifier.connectBuses(
        fromBus: 2,
        toBus: 3,
        r: 0.015,
        x: 0.035,
        bHalf: 0.01,
      );
      notifier.connectBuses(
        fromBus: 1,
        toBus: 3,
        r: 0.02,
        x: 0.04,
      );
      state = container.read(sldWorkspaceProvider);
      expect(state.lines.length, equals(3));

      // 7. Move Bus 3 to new position (verifying 25px grid snap)
      notifier.moveBus(3, const Offset(512.4, 388.9));
      state = container.read(sldWorkspaceProvider);
      final movedBus3 = state.buses.firstWhere((b) => b.busNumber == 3);
      expect(movedBus3.position.dx, equals(500.0));
      expect(movedBus3.position.dy, equals(400.0));

      // 8. Update Bus 3 Equipment
      notifier.updateBusEquipment(
        busNumber: 3,
        pGen: 0.80,
        pLoad: 0.10,
        vMag: 1.03,
      );
      final pfState = container.read(powerFlowProvider);
      final updatedPfBus3 = pfState.buses.firstWhere((b) => b.busNumber == 3);
      expect(updatedPfBus3.pGen, closeTo(0.80, 1e-4));
      expect(updatedPfBus3.pLoad, closeTo(0.10, 1e-4));
      expect(updatedPfBus3.vMag, closeTo(1.03, 1e-4));

      // 9. Execute Power Flow solution on custom sandbox network
      container.read(powerFlowProvider.notifier).calculate();
      final solvedPf = container.read(powerFlowProvider);
      expect(solvedPf.result, isNotNull);
      expect(solvedPf.result!.converged, isTrue);
      expect(solvedPf.result!.voltages.length, equals(3));

      // 10. Test Editor Mode Delete
      notifier.setEditorMode(SldEditorMode.delete);
      expect(container.read(sldWorkspaceProvider).editorMode, equals(SldEditorMode.delete));

      // 11. Remove a line
      final line13 = state.lines.firstWhere((l) => (l.fromBus == 1 && l.toBus == 3) || (l.fromBus == 3 && l.toBus == 1));
      notifier.removeLine(line13.id);
      state = container.read(sldWorkspaceProvider);
      expect(state.lines.any((l) => l.id == line13.id), isFalse);
      expect(state.lines.length, equals(2));

      // 12. Remove Bus 3: should remove Bus 3 and its remaining connected branch (line 2-3)
      notifier.removeBus(3);
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.any((b) => b.busNumber == 3), isFalse);
      expect(state.buses.length, equals(2));
      expect(state.lines.length, equals(1)); // Only line 1-2 remains

      // 13. Remove remaining buses down to 0
      notifier.removeBus(2);
      notifier.removeBus(1);
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.isEmpty, isTrue);
      expect(state.lines.isEmpty, isTrue);

      // 14. Test clearCanvasToSandbox resets completely to blank
      notifier.clearCanvasToSandbox();
      state = container.read(sldWorkspaceProvider);
      expect(state.buses.isEmpty, isTrue);
      expect(state.lines.isEmpty, isTrue);
    });
  });

  group('Phase 3 Dynamic LFC & EMS Engine Benchmarks', () {
    test('LfcTransientEngine: RK4 Primary Droop Reaches Theoretical Steady-State Offset', () {
      // System: H = 5.0 s, D = 0.8 pu, R = 5% (0.05 pu), ΔP_L = 50 MW on 1000 MVA base
      // ΔP_L = 0.05 pu
      // β = D + 1/R = 0.8 + 20.0 = 20.8 pu
      // Δf_ss = -ΔP_L / β = -0.05 / 20.8 = -0.0024038 pu
      // Δf_ss (Hz) = -0.0024038 * 50.0 = -0.12019 Hz
      // f_ss = 50.0 - 0.12019 = 49.8798 Hz
      const params = DynamicLfcParams(
        inertiaH: 5.0,
        dampingD: 0.8,
        droopR: 0.05,
        governorTau: 0.08,
        turbineTau: 0.30,
        stepLoadDeltaPL_MW: 50.0,
        systemMvaBase: 1000.0,
        nominalFreq: 50.0,
        tMax: 30.0,
        dt: 0.01,
      );

      final traj = LfcTransientEngine.simulate(params: params, enableAGC: false);

      expect(traj.isNotEmpty, isTrue);
      expect(traj.first.time, equals(0.0));
      expect(traj.first.frequency_Hz, equals(50.0));

      final finalPoint = traj.last;
      expect(finalPoint.time, closeTo(30.0, 1e-2));

      // Check steady-state frequency deviation matches formula
      final expectedDeltaF_Hz = params.steadyStateDeltaF_Hz;
      expect(expectedDeltaF_Hz, closeTo(-0.12019, 1e-4));
      expect(finalPoint.deltaF_Hz, closeTo(expectedDeltaF_Hz, 2e-3));
      expect(finalPoint.frequency_Hz, closeTo(50.0 + expectedDeltaF_Hz, 2e-3));
    });

    test('LfcTransientEngine: RK4 Secondary AGC Restores Frequency to Nominal 50.0 Hz', () {
      const params = DynamicLfcParams(
        inertiaH: 5.0,
        dampingD: 0.8,
        droopR: 0.05,
        governorTau: 0.08,
        turbineTau: 0.30,
        integralGainKi: 0.5, // secondary integral action
        stepLoadDeltaPL_MW: 50.0,
        systemMvaBase: 1000.0,
        nominalFreq: 50.0,
        tMax: 30.0,
        dt: 0.01,
      );

      final traj = LfcTransientEngine.simulate(params: params, enableAGC: true);

      // In the middle of transient, frequency dips
      final minFreq = traj.map((p) => p.frequency_Hz).reduce((a, b) => a < b ? a : b);
      expect(minFreq, lessThan(49.9));

      // At steady-state (t = 30s), integral action returns frequency to 50.0 Hz
      final finalPoint = traj.last;
      expect(finalPoint.deltaF_Hz, closeTo(0.0, 1e-3));
      expect(finalPoint.frequency_Hz, closeTo(50.0, 1e-3));
    });

    test('EmsConsoleProvider computes telemetry and classifies ACE severity', () {
      final container = ProviderContainer();
      final emsState = container.read(emsConsoleProvider);

      expect(emsState.gridFrequencyHz, closeTo(50.0, 1.0));
      expect(emsState.systemLambda, greaterThan(0.0));
      expect(emsState.totalGenMW, greaterThanOrEqualTo(0.0));

      // Normal zone when ACE is small
      if (emsState.aceMW.abs() <= 5.0) {
        expect(emsState.aceSeverity, equals(AceSeverity.normal));
      } else if (emsState.aceMW.abs() <= 20.0) {
        expect(emsState.aceSeverity, equals(AceSeverity.warning));
      } else {
        expect(emsState.aceSeverity, equals(AceSeverity.emergency));
      }
    });
  });

  group('Phase 3 Widgets Rendering', () {
    testWidgets('BusInspectorSheet renders voltage and injection metrics', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const bus = SldBusNode(
        busNumber: 2,
        name: 'Bus 2 (PV Gen)',
        type: BusType.pv,
        position: Offset(400, 400),
        vMag: 1.04,
        angleDeg: -1.5,
        pGen: 0.50,
        qGen: 0.18,
        pLoad: 0.0,
        qLoad: 0.0,
        qMin: -0.50,
        qMax: 1.00,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BusInspectorSheet(bus: bus),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bus 2 (PV Gen)'), findsOneWidget);
      expect(find.text('Voltage State'), findsOneWidget);
      expect(find.text('1.0400 pu'), findsOneWidget);
      expect(find.text('-1.500°'), findsOneWidget);
      expect(find.text('PV Reactive Limits [Q_min, Q_max]'), findsOneWidget);
      expect(find.text('NORMAL VOLTAGE REGULATION'), findsOneWidget);
    });

    testWidgets('FrequencyTransientChart toggles comparison modes and settings', (tester) async {
      tester.view.physicalSize = const Size(900, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FrequencyTransientChart(
                params: DynamicLfcParams(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Primary Droop'), findsOneWidget);
      expect(find.text('Secondary AGC'), findsOneWidget);
      expect(find.text('Compare Both'), findsOneWidget);

      // Open tuning sliders
      await tester.tap(find.byIcon(Icons.tune_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Step Load Disturbance ΔP_L:'), findsOneWidget);
      expect(find.text('System Inertia Constant H:'), findsOneWidget);
    });

    testWidgets('CustomBusDialog renders generator and load configuration controls', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBusDialog(
              nextBusNumber: 4,
              onSave: ({
                required busNumber,
                required name,
                required type,
                required vMag,
                required angleDeg,
                required pGen,
                required qGen,
                required pLoad,
                required qLoad,
                required qMin,
                required qMax,
                required isVertical,
                required position,
              }) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Add Custom Bus Node'), findsOneWidget);
      expect(find.text('Generator Equipment'), findsOneWidget);
      expect(find.text('Load Demand Equipment'), findsOneWidget);
      expect(find.text('Add Bus to Canvas'), findsOneWidget);
    });

    testWidgets('ConnectBusesDialog renders terminal selectors and branch parameters', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const buses = [
        SldBusNode(busNumber: 1, name: 'Bus 1', type: BusType.slack, position: Offset(100, 100)),
        SldBusNode(busNumber: 2, name: 'Bus 2', type: BusType.pq, position: Offset(300, 100)),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConnectBusesDialog(
              buses: buses,
              initialFromBus: 1,
              initialToBus: 2,
              onConnect: ({
                required fromBus,
                required toBus,
                required r,
                required x,
                required bHalf,
                required tap,
              }) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect Buses with Branch'), findsOneWidget);
      expect(find.text('Terminal Endpoints'), findsOneWidget);
      expect(find.text('Line Impedance & Charging (Per Unit)'), findsOneWidget);
      expect(find.text('Connect Buses'), findsOneWidget);
    });
  });
}
