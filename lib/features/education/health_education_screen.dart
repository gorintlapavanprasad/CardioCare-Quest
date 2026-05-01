import 'package:flutter/material.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';

class HealthEducationScreen extends StatelessWidget {
  const HealthEducationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Health Education'),
      ),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.book, color: AppColors.primary),
            title: Text('What is High Blood Pressure?'),
            subtitle: Text('Learn the basics of hypertension.'),
          ),
          ListTile(
            leading: Icon(Icons.restaurant_menu, color: AppColors.primary),
            title: Text('Healthy Eating for Your Heart'),
            subtitle: Text('Discover the best foods for your heart.'),
          ),
          ListTile(
            leading: Icon(Icons.directions_run, color: AppColors.primary),
            title: Text('The Importance of Physical Activity'),
            subtitle: Text('Find out how exercise can lower your BP.'),
          ),
          ListTile(
            leading: Icon(Icons.spa, color: AppColors.primary),
            title: Text('Managing Stress'),
            subtitle: Text('Learn techniques to reduce stress.'),
          ),
        ],
      ),
    );
  }
}
