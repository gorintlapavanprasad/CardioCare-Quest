import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For copy to clipboard
import '../../core/theme/app_colors.dart';
import 'login_screen.dart';
// import '../dashboard/dashboard_screen.dart'; // Uncomment when ready

class QuestCompleteScreen extends StatelessWidget {
  final String participantId;

  const QuestCompleteScreen({super.key, required this.participantId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.pageBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline, size: 100, color: AppColors.viridis3),
                const SizedBox(height: 32),
                Text(
                  "Quest Initialized!",
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 36),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Your profile has been securely created. Please save your Participant ID below. You will need it if you ever switch devices.",
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                
                // ─── The ID Display Card ───
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, 10))],
                  ),
                  child: Column(
                    children: [
                      Text("PARTICIPANT ID", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.viridis4.withValues(alpha: 0.7), letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text(participantId, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: AppColors.viridis4, letterSpacing: 2)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: participantId));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ID Copied to Clipboard!")));
                  },
                  icon: const Icon(Icons.copy, color: AppColors.placeholder),
                  label: const Text("Copy ID", style: TextStyle(color: AppColors.placeholder)),
                ),
                
                const Spacer(),
                
                // ─── Final Entry Button ───
                // ─── Final Entry Button ───
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      // Route to LoginScreen instead of the Placeholder
                      MaterialPageRoute(builder: (context) => const LoginScreen()), 
                    );
                  },
                  child: const Text("PROCEED TO LOGIN"),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
