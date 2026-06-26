import 'package:flutter/material.dart';
import 'desktop_layout.dart';
import 'mobile_layout.dart';

class ResponsiveLayout extends StatelessWidget {
  const ResponsiveLayout({super.key});

  @override
  Widget build(BuildContext content) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 800) {
          return const DesktopLayout();
        } else {
          return const MobileLayout();
        }
      },
    );
  }
}
