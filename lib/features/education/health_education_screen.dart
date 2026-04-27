import 'package:flutter/material.dart';

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
            leading: Icon(Icons.book),
            title: Text('What is High Blood Pressure?'),
            subtitle: Text('Learn the basics of hypertension.'),
          ),
          ListTile(
            leading: Icon(Icons.restaurant_menu),
            title: Text('Healthy Eating for Your Heart'),
            subtitle: Text('Discover the best foods for your heart.'),
          ),
          ListTile(
            leading: Icon(Icons.directions_run),
            title: Text('The Importance of Physical Activity'),
            subtitle: Text('Find out how exercise can lower your BP.'),
          ),
          ListTile(
            leading: Icon(Icons.spa),
            title: Text('Managing Stress'),
            subtitle: Text('Learn techniques to reduce stress.'),
          ),
        ],
      ),
    );
  }
}

