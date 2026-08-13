import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cardio_care_quest/core/theme/app_colors.dart';
import 'package:cardio_care_quest/core/providers/user_data_manager.dart';
import 'package:cardio_care_quest/core/hooks/hooks.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

// Meal diary: log how a meal felt, what you ate, and an optional photo.
// Distinct from the DASH Diet Game.

class DietLogScreen extends StatefulWidget {
  const DietLogScreen({super.key});

  @override
  State<DietLogScreen> createState() => _DietLogScreenState();
}

class _DietLogScreenState extends State<DietLogScreen> {
  int _mealRating = 2; // 0-4 scale
  final TextEditingController _mealNotesController = TextEditingController();
  XFile? _image;
  bool _isSaving = false;

  // Opens the gallery and stores the picked photo.
  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    setState(() {
      _image = image;
    });
  }

  // Saves the meal, awards 25 pts, and closes. No-op if notes and photo are both empty.
  Future<void> _saveMeal() async {
    final uid = Provider.of<UserDataProvider>(context, listen: false).uid;
    if (uid.isEmpty) return;
    if (_mealNotesController.text.isEmpty && _image == null) return;

    setState(() => _isSaving = true);

    try {
      final String today = DateTime.now().toIso8601String().split('T')[0];

      await DailyLogHooks.logMeal(
        uid: uid,
        mealNotes: _mealNotesController.text,
        mealRating: _mealRating,
        hasMealPhoto: _image != null,
      );

      if (mounted) {
        PointsHooks.applyIncrements(context, const {
          'points': 25,
          'mealsLogged': 1,
        });
        PointsHooks.applySets(context, {'lastLogDate': today});
        Navigator.of(context).pop(25);
      }
    } catch (e) {
      debugPrint('SAVE ERROR: $e');
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Your Meal'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMealRating(),
            const SizedBox(height: 32),
            _buildMealNotes(),
            const SizedBox(height: 32),
            _buildPhotoUpload(),
            const SizedBox(height: 48),
            _buildSaveButton(),
            const SizedBox(height: 48),
            _buildNutritionTip(),
          ],
        ),
      ),
    );
  }

  // 5 emoji faces. The selected one grows with a highlighted circle.
  Widget _buildMealRating() {
    final List<String> ratings = ['😞', '😕', '😐', '🙂', '😄'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'How did this meal make you feel?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.title),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(ratings.length, (index) {
            final isSelected = _mealRating == index;
            return GestureDetector(
              onTap: () => setState(() => _mealRating = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Opacity(
                  opacity: isSelected ? 1.0 : 0.5,
                  child: Text(
                    ratings[index],
                    style: TextStyle(fontSize: isSelected ? 36 : 28),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  // "What did you eat?" text field.
  Widget _buildMealNotes() {
    return TextField(
      controller: _mealNotesController,
      decoration: InputDecoration(
        labelText: 'What did you eat?',
        hintText: 'e.g., Blue corn mush, mutton stew, salad...',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.cardBorder),
        ),
      ),
      maxLines: 3,
    );
  }

  // Optional photo box. Shows the picked photo, or a camera icon if none.
  Widget _buildPhotoUpload() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add a photo (optional)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _image == null
                ? const Icon(Icons.camera_alt, size: 48, color: AppColors.placeholder)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(_image!.path),
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // Save button. Disabled and shows a spinner while saving.
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: _isSaving ? null : _saveMeal,
        child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('Save Meal', style: TextStyle(fontSize: 18)),
      ),
    );
  }

  // Tip box at the bottom.
  Widget _buildNutritionTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Text(
        'Tip: Choosing whole grains like oats and brown rice can help manage blood pressure.',
        style: TextStyle(color: AppColors.primaryDark),
      ),
    );
  }
}

