import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/project_screen.dart';
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
    ProjectScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              // 左メニューラベルの表示
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('ホーム'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder),
                label: Text('プロジェクト'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.home),
                label: Text('アナリティクス'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('設定'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: screens[selectedIndex]),
        ],
      ),
    );
  }
}
