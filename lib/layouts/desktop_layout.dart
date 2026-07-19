import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/organization_screen.dart';
import '../screens/project_screen.dart';
import '../screens/task_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/settings_screen.dart';

class DesktopLayout extends StatefulWidget {
  const DesktopLayout({super.key});

  @override
  State<DesktopLayout> createState() => _DesktopLayoutState();
}

class _DesktopLayoutState extends State<DesktopLayout> {
  int selectedIndex = 0;

  final screens = const [
    HomeScreen(),
    OrganizationScreen(),
    ProjectScreen(),
    TaskScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final selectedScreen = screens[selectedIndex.clamp(0, screens.length - 1)];

    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              extended: true,
              minExtendedWidth: 180,
              scrollable: true,
              onDestinationSelected: (index) {
                setState(() {
                  selectedIndex = index;
                });
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home),
                  label: Text('ホーム'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.apartment),
                  label: Text('組織'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.folder),
                  label: Text('プロジェクト'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.task_alt),
                  label: Text('タスク'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.bar_chart),
                  label: Text('アナリティクス'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.settings),
                  label: Text('設定'),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: selectedScreen),
        ],
      ),
    );
  }
}
