import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ─── NEW: Official Auth
import 'package:provider/provider.dart'; // ─── NEW: State Management
import '../../../core/theme/app_colors.dart';
import 'package:cardio_care_quest/user_data_manager.dart';

class BPLogScreen extends StatefulWidget {
  const BPLogScreen({super.key});

  @override
  State<BPLogScreen> createState() => _BPLogScreenState();
}

class _BPLogScreenState extends State<BPLogScreen> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  bool _isSaving = false;

Future<void> _saveBPReading() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_systolicController.text.isEmpty || _diastolicController.text.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final int sys = int.parse(_systolicController.text);
      final int dia = int.parse(_diastolicController.text);
      String today = DateTime.now().toIso8601String().split('T')[0];
      
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch(); // Use batch to update Profile and Leaderboard together

      // ─── CHANGED: Point to 'users' collection ───
      final userRef = firestore.collection('users').doc(user.uid);

      // 1. Save detailed log for history (Nested under the user)
      final logRef = userRef.collection('dailyLogs').doc(today);
      batch.set(logRef, {
        'systolic': sys,
        'diastolic': dia,
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. ⚡ DASHBOARD SYNC: Update root fields (Using new Netgauge schema names)
      batch.update(userRef, {
        'totalXP': FieldValue.increment(50),          // Changed from 'xp'
        'totalSessions': FieldValue.increment(1),     // Changed from 'measurementsTaken'
        'lastSystolic': sys,       
        'lastDiastolic': dia,      
        'lastLogDate': today,      
      });

      // 3. 🏆 LEADERBOARD SYNC: Ensure researchers see the new XP
      final leaderboardRef = firestore.collection('leaderboard').doc(user.uid);
      batch.update(leaderboardRef, {
        'score': FieldValue.increment(50),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Commit all writes at once
      await batch.commit();

      if (mounted) {
        // Refresh the provider "Brain"
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint("❌ SAVE ERROR: $e");
      if (mounted) setState(() => _isSaving = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text("Daily BP Quest", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.title,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Log your morning reading to earn 50 XP!",
              style: TextStyle(color: AppColors.subtitle, fontSize: 16),
            ),
            const SizedBox(height: 32),
            
            _buildInputLabel("Systolic (Upper Number)"),
            _buildNumericField(_systolicController, "e.g. 120"),
            
            const SizedBox(height: 24),
            
            _buildInputLabel("Diastolic (Lower Number)"),
            _buildNumericField(_diastolicController, "e.g. 80"),
            
            const SizedBox(height: 48),
            
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.viridis2,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _isSaving ? null : _saveBPReading,
                child: _isSaving 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("COMPLETE LOG", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.title)),
    );
  }

  Widget _buildNumericField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        suffixText: "mmHg",
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.viridis2, width: 2),
        ),
      ),
    );
  }
}