import 'package:flutter/material.dart';
import 'home_tab.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: HomeTab(),
    );
  }
}
