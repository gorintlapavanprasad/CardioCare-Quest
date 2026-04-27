import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class BPLogScreen extends StatefulWidget {
  const BPLogScreen({super.key});

  @override
  State<BPLogScreen> createState() => _BPLogScreenState();
}

class _BPLogScreenState extends State<BPLogScreen> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  
  bool _isSaving = false;
  int _selectedMood = 2; // 0-4 scale, 2 is neutral

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
    super.dispose();
  }

  Future<void> _saveBPReading() async {
    final userDataProvider = Provider.of<UserDataProvider>(context, listen: false);
    final uid = userDataProvider.uid;
    if (uid.isEmpty || _systolicController.text.isEmpty || _diastolicController.text.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final int sys = int.parse(_systolicController.text);
      final int dia = int.parse(_diastolicController.text);
      String today = DateTime.now().toIso8601String().split('T')[0];

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      final userRef = firestore.collection(FirestorePaths.userData).doc(uid);

      // 1. Save to daily logs
      final logRef = userRef.collection(FirestorePaths.dailyLogs).doc(today);
      batch.set(logRef, {
        'systolic': sys,
        'diastolic': dia,
        'mood': _selectedMood,
        'timestamp': FieldValue.serverTimestamp(),
        'date': today,
      }, SetOptions(merge: true));

      // 2. Update user stats
      batch.update(userRef, {
        'points': FieldValue.increment(50),
        'totalSessions': FieldValue.increment(1),
        'measurementsTaken': FieldValue.increment(1),
        'lastSystolic': sys,
        'lastDiastolic': dia,
        'lastLogDate': today, // Keep this as a general "Last Active" tracker
        'lastBPLogDate': today, // ADD THIS specific tracker just for the BP quest
      });

      // 3. Log the event
      final eventRef = firestore.collection(FirestorePaths.events).doc();
      batch.set(eventRef, {
        'id': eventRef.id,
        'userId': uid,
        'event': 'bp_reading_logged',
        'systolic': sys,
        'diastolic': dia,
        'mood': _selectedMood,
        'timestamp': FieldValue.serverTimestamp(),
        'syncedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) {
        await Provider.of<UserDataProvider>(context, listen: false).fetchUserData();
        
        if (mounted) Navigator.of(context).pop(50);
      }
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // OPTIMIZATION: Use a Stream instead of a Future to prevent redundant reads on UI state changes
  Stream<QuerySnapshot> _getRecentReadingsStream() {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.dailyLogs)
        .orderBy('timestamp', descending: true)
        .limit(7)
        .snapshots(); // Listen to real-time changes
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Log Your Reading'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInputSection(),
            const SizedBox(height: 32),
            _buildMoodTracker(),
            const SizedBox(height: 48),
            _buildSaveButton(),
            const SizedBox(height: 48),
            _buildChartSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection() {
    return Row(
      children: [
        Expanded(child: _buildNumericField(_systolicController, 'Systolic')),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Text(
            '/',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.bold,
              color: AppColors.placeholder,
            ),
          ),
        ),
        Expanded(child: _buildNumericField(_diastolicController, 'Diastolic')),
      ],
    );
  }

  Widget _buildNumericField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: InputBorder.none,
      ),
    );
  }

  Widget _buildMoodTracker() {
    final List<String> moods = ['😞', '😕', '😐', '🙂', '😄'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How are you feeling today?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(moods.length, (index) {
            final isSelected = _selectedMood == index;
            return GestureDetector(
              onTap: () => setState(() => _selectedMood = index),
              child: Opacity(
                opacity: isSelected ? 1.0 : 0.5,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    moods[index],
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: _isSaving ? null : _saveBPReading,
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Save Reading', style: TextStyle(fontSize: 18)),
      ),
    );
  }

  Widget _buildChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your 7-Day Trend',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 200,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: _getRecentReadingsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No readings yet.'));
              }

              final readings = snapshot.data!.docs.reversed.toList();
              final spotsSys = <FlSpot>[];
              final spotsDia = <FlSpot>[];

              for (int i = 0; i < readings.length; i++) {
                final reading = readings[i].data() as Map<String, dynamic>;
                spotsSys.add(FlSpot(i.toDouble(), (reading['systolic'] as int).toDouble()));
                spotsDia.add(FlSpot(i.toDouble(), (reading['diastolic'] as int).toDouble()));
              }

              String formatReadingDate(int index) {
                final reading = readings[index].data() as Map<String, dynamic>;
                final timestampValue = reading['timestamp'];
                
                DateTime date;
                if (timestampValue is Timestamp) {
                  date = timestampValue.toDate();
                } else if (reading.containsKey('date')) {
                  date = DateTime.tryParse(reading['date'] as String) ?? DateTime.now();
                } else {
                  date = DateTime.now();
                }
                return DateFormat('d MMM').format(date);
              }

              return LineChart(
                LineChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < readings.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                formatReadingDate(index),
                                style: const TextStyle(fontSize: 10),
                              ),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    _lineChartBarData(spotsSys, AppColors.primary),
                    _lineChartBarData(spotsDia, AppColors.secondary),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  LineChartBarData _lineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 4,
      isStrokeCapRound: true,
      dotData: FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.1),
      ),
    );
  }
}
