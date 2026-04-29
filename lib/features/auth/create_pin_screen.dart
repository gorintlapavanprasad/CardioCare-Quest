import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';
import '../../core/services/offline_queue.dart';
import 'quest_complete_screen.dart'; // Make sure this is imported!

class CreatePinScreen extends StatefulWidget {
  final String participantId;
  const CreatePinScreen({super.key, required this.participantId});

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  String _pin = "";
  bool _isSaving = false;

Future<void> _savePin() async {
    if (_pin.length < 4) return;
    setState(() => _isSaving = true);
    
    try {
      await GetIt.instance<OfflineQueue>().enqueue(PendingOp.update(
        '${FirestorePaths.userData}/${widget.participantId}',
        {'transferPin': _pin},
      ));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => QuestCompleteScreen(participantId: widget.participantId)),
        );
      }
    } catch (e) {
      debugPrint("Error saving PIN: $e");
      if (mounted) setState(() => _isSaving = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.pageBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_outline, size: 80, color: AppColors.viridis2),
                const SizedBox(height: 24),
                Text("Secure Your Account", style: Theme.of(context).textTheme.displayLarge, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  "Create a 4-digit Transfer PIN. You will only need this if you upgrade your phone.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 48),
                
                TextField(
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  obscureText: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 40, letterSpacing: 16),
                  onChanged: (val) => setState(() => _pin = val),
                  decoration: InputDecoration(
                    counterText: "",
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    hintText: "••••",
                  ),
                ),
                const SizedBox(height: 48),
                
                ElevatedButton(
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                  onPressed: (_pin.length == 4 && !_isSaving) ? _savePin : null,
                  child: _isSaving 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                      : const Text("SAVE & COMPLETE QUEST"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

