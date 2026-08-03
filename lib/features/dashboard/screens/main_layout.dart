// The outer shell of the app's main area. Right now it just wraps the
// home screen in a Scaffold. Kept as its own file so extra shell things
// (like a bottom nav bar) can be added here later without touching HomeTab.

import 'package:flutter/material.dart';
import 'home_tab.dart';

// The app shell - currently just shows the HomeTab.
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: HomeTab(),
    );
  }
}
