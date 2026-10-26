import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powerflow_studio/main.dart';

void main() {
  testWidgets('PowerFlow Studio smoke test and calculation', (WidgetTester tester) async {
    // Set a large screen size to view lists comfortably
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: PowerFlowStudioApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify navigation destinations render
    expect(find.text('SLD Canvas'), findsWidgets);
    expect(find.text('EMS Console'), findsWidgets);
    expect(find.text('Power Flow'), findsWidgets);
    expect(find.text('Dispatch'), findsWidgets);
    expect(find.text('Frequency'), findsWidgets);

    // Initial screen is SLD Schematic Canvas
    expect(find.text('SLD Schematic Canvas'), findsOneWidget);
    expect(find.text('3-Bus Saadat'), findsOneWidget);

    // Navigate to Power Flow screen
    await tester.tap(find.text('Power Flow').first);
    await tester.pumpAndSettle();

    // Verify 3-bus network in Power Flow screen
    expect(find.text('Bus 1 (Slack)'), findsOneWidget);
    expect(find.text('Bus 2 (PV Gen)'), findsOneWidget);
    expect(find.text('Bus 3 (PQ Load)'), findsOneWidget);

    // Solve Power Flow
    final solveButton = find.text('Solve Power Flow');
    expect(solveButton, findsOneWidget);
    await tester.tap(solveButton);
    await tester.pumpAndSettle();

    // Verify convergence banner appears
    expect(find.textContaining('Converged'), findsWidgets);

    // Navigate to EMS Console screen
    await tester.tap(find.text('EMS Console').first);
    await tester.pumpAndSettle();

    expect(find.text('EMS / SCADA Dispatch Console'), findsOneWidget);
    expect(find.text('Area Control Error (ACE) Indicator'), findsOneWidget);
  });
}
