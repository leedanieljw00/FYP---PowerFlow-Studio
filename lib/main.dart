import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/economic_dispatch/views/economic_dispatch_screen.dart';
import 'features/ems_console/views/ems_dashboard_screen.dart';
import 'features/formula_sheet/views/formula_sheet_screen.dart';
import 'features/load_frequency_control/views/lfc_screen.dart';
import 'features/power_flow/views/power_flow_screen.dart';
import 'features/power_flow/views/step_inspection_screen.dart';
import 'features/sld_workspace/views/sld_canvas_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: PowerFlowStudioApp(),
    ),
  );
}

class PowerFlowStudioApp extends StatelessWidget {
  const PowerFlowStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primarySeed = Color(0xFF0F3A66); // Engineering Deep Blue / Navy
    const secondarySeed = Color(0xFF00897B); // Electric Teal

    return MaterialApp(
      title: 'PowerFlow Studio - EE4530',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primarySeed,
          secondary: secondarySeed,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primarySeed,
          secondary: secondarySeed,
          brightness: Brightness.dark,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    final tabParam = Uri.base.queryParameters['tab'];
    if (tabParam != null) {
      final tabInt = int.tryParse(tabParam);
      if (tabInt != null && tabInt >= 0 && tabInt < _screens.length) {
        _currentIndex = tabInt;
      } else {
        switch (tabParam.toLowerCase()) {
          case 'sld':
            _currentIndex = 0;
            break;
          case 'ems':
            _currentIndex = 1;
            break;
          case 'powerflow':
            _currentIndex = 2;
            break;
          case 'dispatch':
          case 'ed':
            _currentIndex = 3;
            break;
          case 'frequency':
          case 'lfc':
            _currentIndex = 4;
            break;
          case 'inspection':
            _currentIndex = 5;
            break;
          case 'formulas':
            _currentIndex = 6;
            break;
        }
      }
    }
  }

  final List<Widget> _screens = const [
    SldCanvasScreen(),
    EmsDashboardScreen(),
    PowerFlowScreen(),
    EconomicDispatchScreen(),
    LfcScreen(),
    StepInspectionScreen(),
    FormulaSheetScreen(),
  ];

  static const List<_NavDestinationData> _destinations = [
    _NavDestinationData(
      icon: Icons.hub_outlined,
      selectedIcon: Icons.hub,
      label: 'SLD Canvas',
    ),
    _NavDestinationData(
      icon: Icons.analytics_outlined,
      selectedIcon: Icons.analytics,
      label: 'EMS Console',
    ),
    _NavDestinationData(
      icon: Icons.settings_input_component_outlined,
      selectedIcon: Icons.settings_input_component,
      label: 'Power Flow',
    ),
    _NavDestinationData(
      icon: Icons.monetization_on_outlined,
      selectedIcon: Icons.monetization_on,
      label: 'Dispatch',
    ),
    _NavDestinationData(
      icon: Icons.speed_outlined,
      selectedIcon: Icons.speed,
      label: 'Frequency',
    ),
    _NavDestinationData(
      icon: Icons.insights_outlined,
      selectedIcon: Icons.insights,
      label: 'Inspection',
    ),
    _NavDestinationData(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Formulas',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bolt,
                          color: Theme.of(context).colorScheme.primary,
                          size: 32,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'PowerFlow\nStudio',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: _destinations
                      .map((d) => NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ))
                      .toList(),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: _screens,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: _destinations
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon),
                      selectedIcon: Icon(d.selectedIcon),
                      label: d.label,
                    ))
                .toList(),
          ),
        );
      },
    );
  }
}

class _NavDestinationData {
  const _NavDestinationData({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

