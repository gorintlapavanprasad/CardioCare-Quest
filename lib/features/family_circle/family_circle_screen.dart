import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';

class FamilyCircleScreen extends StatelessWidget {
  const FamilyCircleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Circle'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection(FirestorePaths.userData).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!.docs;
          int totalPoints = 0;
          int totalSteps = 0;
          for (var doc in users) {
            final data = doc.data() as Map<String, dynamic>;
            totalPoints += (data['points'] as num?)?.toInt() ?? (data['totalXP'] as num?)?.toInt() ?? 0;
            totalSteps += (data['totalSteps'] as num?)?.toInt() ?? 0;
          }

          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              _buildSharedQuestCard(totalSteps),
              const SizedBox(height: 32),
              const Text(
                'Family Members',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.title),
              ),
              const SizedBox(height: 16),
              ...users.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final String name = data['basicInfo']?['firstName'] ?? 'Explorer';
                final String sys = data['lastSystolic']?.toString() ?? '--';
                final String dia = data['lastDiastolic']?.toString() ?? '--';
                return _buildFamilyMemberCard(name, 'Family Member', '$sys/$dia mmHg', Icons.person);
              }),
              const SizedBox(height: 32),
              _buildEncouragementBoard(totalPoints),
            ],
          );
        }
      ),
    );
  }

  Widget _buildSharedQuestCard(int totalSteps) {
    const int goalSteps = 10000;
    final double progress = (totalSteps / goalSteps).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'Shared Family Quest',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Walk a total of 10,000 steps together!',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: AppColors.primaryDark,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                '$totalSteps / $goalSteps steps',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilyMemberCard(String name, String role, String bp, IconData icon) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      margin: const EdgeInsets.only(bottom: 12.0),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: AppColors.secondary.withValues(alpha: 0.1),
          radius: 28,
          child: Icon(icon, color: AppColors.secondary, size: 32),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.title)),
        subtitle: Text(role, style: const TextStyle(color: AppColors.subtitle)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(bp, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.title)),
            const Text('Today', style: TextStyle(fontSize: 12, color: AppColors.subtitle)),
          ],
        ),
      ),
    );
  }

  Widget _buildEncouragementBoard(int totalPoints) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Text(
            'Keep it up!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.title),
          ),
          const SizedBox(height: 8),
          Text(
            'Your family has earned $totalPoints points together this week.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.subtitle),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildAvatarPile(Icons.elderly_woman),
              _buildAvatarPile(Icons.woman),
              _buildAvatarPile(Icons.man),
              _buildAvatarPile(Icons.person),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildAvatarPile(IconData icon) {
    return CircleAvatar(
      backgroundColor: Colors.white,
      radius: 20,
      child: Icon(icon, color: AppColors.accent),
    );
  }
}

