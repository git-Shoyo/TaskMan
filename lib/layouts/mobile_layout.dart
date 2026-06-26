import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/project_screen.dart';
import '../screens/analytics_screen.dart';
import '../screens/settings_screen.dart';

class MobileLayout extends StatefulWidget {
  const MobileLayout({super.key});

  @override
  State<MobileLayout> createState() => _MobileLayoutState();
}

class _MobileLayoutState extends State<MobileLayout> {
  int selectedIndex = 0;

  final screens = const [
    HomeScreen(),
    ProjectScreen(),
    AnalyticsScreen(),
    SettingsScreen(),
  ];

  final titles = const ['ホーム', 'プロジェクト', 'アナリティクス', '設定'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titles[selectedIndex])),
      body: screens[selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'ホーム'),
          NavigationDestination(icon: Icon(Icons.folder), label: 'プロジェクト'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'アナリティクス'),
          NavigationDestination(icon: Icon(Icons.settings), label: '設定'),
        ],
      ),
    );
  }
}
