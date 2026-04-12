import 'package:flutter/material.dart';
// For debugPrint
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme/app_colors.dart';

class AuthProvider extends ChangeNotifier {
  int _currentStep = 0;
  final int totalSteps = 14; // ─── CHANGE THIS TO 14 ───
  final Map<String, dynamic> _formData = {};
  final bool _isSubmitting = false;

  int get currentStep => _currentStep;
  
  Map<String, dynamic> get formData => _formData;
  bool get isSubmitting => _isSubmitting;

  Color get progressColor {
    double t = (_currentStep + 1) / totalSteps;
    if (t < 0.25) return AppColors.viridis0;
    if (t < 0.50) return AppColors.viridis1;
    if (t < 0.75) return AppColors.viridis2;
    if (t < 0.95) return AppColors.viridis3;
    return AppColors.viridis4;
  }

  void updateField(String key, dynamic value) {
    _formData[key] = value;
    debugPrint("🛠️ DEBUG: Form Field Updated -> $key: $value");
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < totalSteps - 1) {
      _currentStep++;
      debugPrint("🛠️ DEBUG: Moved to Step ${_currentStep + 1}");
      notifyListeners();
    }
  }

  void prevStep() {
    if (_currentStep > 0) {
      _currentStep--;
      debugPrint("🛠️ DEBUG: Moved back to Step ${_currentStep + 1}");
      notifyListeners();
    }
  }

  // ─── FINAL SUBMISSION LOGIC ───
// ─── FINAL SUBMISSION LOGIC ───
 Future<String?> submitQuest() async {
    try {
      // 1. Generate a new Participant ID (e.g., CCQ-1234)
      String newId = "CCQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

      // 2. Define the known non-survey keys to separate them from the 35 questions
     List<String> basicKeys = [
        'firstName', 'lastName', 'zipCode', 'state', 'city', 
        'gender', 'genderSpecify', 'raceSpecify', 
        // ─── ADD THE NEW FIELDS HERE ───
        'ethnicity', 'race', 'education', 
        'foodTracking', 'takingMedication', 'medicationName',
        // ───────────────────────────────
        'playerMode', 'playerCount', 'bpAppUsage', 'bpAppType',
        'additionalNotes', 'consentAgreement', 'digitalSignature'
      ];

      // 3. Create the clean, grouped database schema
      // 3. Create the clean, grouped database schema
      Map<String, dynamic> structuredData = {
        'participantId': newId,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        
        'basicInfo': {
          'firstName': formData['firstName'],
          'lastName': formData['lastName'],
          'zipCode': formData['zipCode'],
          'state': formData['state'],
          'city': formData['city'],
        },

        // ─── ADDED: PhenX Demographics Group ───
        'demographics': {
          'gender': formData['gender'],
          'genderSpecify': formData['genderSpecify'],
          'ethnicity': formData['ethnicity'],
          'race': formData['race'],
          'education': formData['education'],
          'raceSpecify': formData['raceSpecify'],
        },

        // ─── ADDED: Health Habits Group ───
        'healthHabits': {
          'foodTracking': formData['foodTracking'],
          'takingMedication': formData['takingMedication'],
          'medicationName': formData['medicationName'],
        },

        'appExperience': {
          'bpAppUsage': formData['bpAppUsage'],
          'bpAppType': formData['bpAppType'],
        },

        'surveyResponses': {}, 

        'consent': {
          'additionalNotes': formData['additionalNotes'],
          'consentAgreement': formData['consentAgreement'],
          'digitalSignature': formData['digitalSignature'], 
        }
      };

      // 4. Automatically filter survey questions
      // Everything NOT in basicKeys goes into surveyResponses
      formData.forEach((key, value) {
        if (!basicKeys.contains(key)) {
          structuredData['surveyResponses'][key] = value;
        }
      });

      // 5. Clean up any nulls (in case they skipped optional fields like 'bpAppType')
      _removeNulls(structuredData);

      // 6. Save to Firebase!
      await FirebaseFirestore.instance.collection('users').doc(newId).set(structuredData);

      return newId;
    } catch (e) {
      debugPrint("Error saving to Firebase: $e");
      return null;
    }
  }

  // Helper function to keep the database pristine by removing empty fields
  void _removeNulls(Map<String, dynamic> map) {
    map.removeWhere((key, value) {
      if (value == null) return true;
      if (value is Map<String, dynamic>) {
        _removeNulls(value);
        return value.isEmpty;
      }
      return false;
    });
  }
  
  }