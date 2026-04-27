import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/constants/firestore_paths.dart';

class HeartStatisticsScreen extends StatelessWidget {
  const HeartStatisticsScreen({super.key});

  Stream<QuerySnapshot> _getReadingsStream(BuildContext context) {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return const Stream.empty();
    
    return FirebaseFirestore.instance
        .collection(FirestorePaths.userData)
        .doc(uid)
        .collection(FirestorePaths.dailyLogs)
        .orderBy('timestamp', descending: false) // Chronological order for the chart
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Heart Statistics'),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _getReadingsStream(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final readings = snapshot.data!.docs;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Blood Pressure Over Time',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.title),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Track your systolic and diastolic trends.',
                  style: TextStyle(fontSize: 14, color: AppColors.subtitle),
                ),
                const SizedBox(height: 24),
                _buildLegend(),
                const SizedBox(height: 24),
                _buildChartCard(readings),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.monitor_heart_outlined, size: 80, color: AppColors.subtitle.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'No Data Yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.title),
          ),
          const SizedBox(height: 8),
          const Text(
            'Log your blood pressure to see your trends.',
            style: TextStyle(color: AppColors.subtitle),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem('Systolic', AppColors.primary),
        const SizedBox(width: 24),
        _legendItem('Diastolic', AppColors.secondary),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.title)),
      ],
    );
  }

  Widget _buildChartCard(List<QueryDocumentSnapshot> readings) {
    final spotsSys = <FlSpot>[];
    final spotsDia = <FlSpot>[];

    for (int i = 0; i < readings.length; i++) {
      final data = readings[i].data() as Map<String, dynamic>;
      spotsSys.add(FlSpot(i.toDouble(), (data['systolic'] as int).toDouble()));
      spotsDia.add(FlSpot(i.toDouble(), (data['diastolic'] as int).toDouble()));
    }

    String formatReadingDate(int index) {
      if (index < 0 || index >= readings.length) return '';
      final data = readings[index].data() as Map<String, dynamic>;
      
      DateTime date;
      if (data['timestamp'] is Timestamp) {
        date = (data['timestamp'] as Timestamp).toDate();
      } else if (data.containsKey('date')) {
        date = DateTime.tryParse(data['date'] as String) ?? DateTime.now();
      } else {
        date = DateTime.now();
      }
      return DateFormat('MMM d').format(date);
    }

    return Container(
      height: 350,
      padding: const EdgeInsets.only(right: 24, left: 8, top: 24, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 20,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.cardBorder.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  // Only show label every few points if there are many readings to avoid crowding
                  if (value % (readings.length > 7 ? 2 : 1) != 0) return const Text('');
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      formatReadingDate(value.toInt()),
                      style: const TextStyle(fontSize: 10, color: AppColors.subtitle),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: 20,
                getTitlesWidget: (value, meta) {
                  return Text(
                    value.toInt().toString(),
                    style: const TextStyle(fontSize: 10, color: AppColors.subtitle),
                  );
                },
              ),
            ),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            _createLineData(spotsSys, AppColors.primary),
            _createLineData(spotsDia, AppColors.secondary),
          ],
        ),
      ),
    );
  }

  LineChartBarData _createLineData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: color,
      barWidth: 4,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => CirclePainter(
          radius: 4,
          color: Colors.white,
          strokeWidth: 2,
          strokeColor: color,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: color.withValues(alpha: 0.1),
      ),
    );
  }
}

 class CirclePainter extends FlDotPainter {
  final double radius;
  final Color color;
  final Color strokeColor;
  final double strokeWidth;

  CirclePainter({
    required this.radius, 
    required this.color, 
    required this.strokeColor, 
    required this.strokeWidth
  });

  // 1. ADDED: Required by newer versions of fl_chart
  @override
  Color get mainColor => color; 

  @override
  void draw(Canvas canvas, FlSpot spot, Offset offsetInCanvas) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(offsetInCanvas, radius, paint);
    canvas.drawCircle(offsetInCanvas, radius, strokePaint);
  }

  @override
  Size getSize(FlSpot spot) => Size(radius * 2, radius * 2);

  @override
  List<Object?> get props => [radius, color, strokeColor, strokeWidth];

  // 2. ADDED: Required by newer versions of fl_chart for animations
  @override
  FlDotPainter lerp(FlDotPainter a, FlDotPainter b, double t) {
    return this; 
  }
}