import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ─── UPDATED IMPORT ───
import '../../../core/theme/app_colors.dart';

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
    if (_systolicController.text.isEmpty || _diastolicController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both numbers")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // ─── UPDATED: USE SHARED PREFERENCES TO PREVENT HANGING ON WEB ───
      final prefs = await SharedPreferences.getInstance();
      String? participantId = prefs.getString('participant_id');
      
      if (participantId == null) {
        throw Exception("User ID not found. Please log in again.");
      }
      // ────────────────────────────────────────────────────────────────

      String today = DateTime.now().toIso8601String().split('T')[0];
      
      await FirebaseFirestore.instance
          .collection('users').doc(participantId)
          .collection('dailyLogs').doc(today)
          .set({
        'systolic': int.parse(_systolicController.text),
        'diastolic': int.parse(_diastolicController.text),
        'timestamp': FieldValue.serverTimestamp(),
        'taskCompleted': true,
      }, SetOptions(merge: true));

      if (mounted) {
        // Returning true triggers the celebration modal on the HomeTab
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint("❌ SAVE ERROR: $e");
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
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