import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // ─── NEW: Official Auth
import '../../core/theme/app_colors.dart';

class AuthProvider extends ChangeNotifier {
  int _currentStep = 0;
  final int totalSteps = 14; 
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
    debugPrint("🛠️ Form Field Updated -> $key: $value");
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < totalSteps - 1) {
      _currentStep++;
      notifyListeners();
    }
  }

  void prevStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }


// ─── PROFESSIONAL NETGAUGE HYBRID ONBOARDING SUBMISSION ───
  Future<String?> submitQuest() async {
    try {
      // 1. Authenticate to get a true Firebase UID
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;

      // Generate a friendly display ID for the UI
      String displayId = "CCQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}";

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch(); // ─── NEW: Batch write for multiple top-level collections

      // ─── 1. ROOT DOCUMENT (users/{uid}) ───
      final userRef = firestore.collection('users').doc(uid);
      batch.set(userRef, {
        'uid': uid,
        'participantId': displayId,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'basicInfo': {
          'firstName': formData['firstName'] ?? 'Explorer',
          'lastName': formData['lastName'] ?? '',
          'zipCode': formData['zipCode'] ?? '',
          'state': formData['state'] ?? '',
          'city': formData['city'] ?? '',
        },
        // Flattening Demographics directly into the root profile for easier reading
        'demographics': {
          'gender': formData['gender'],
          'ethnicity': formData['ethnicity'],
          'race': formData['race'],
          'education': formData['education'],
          'foodTracking': formData['foodTracking'],
          'takingMedication': formData['takingMedication'],
        },
        // Initialize Dashboard/Game Stats to match Netgauge
        'totalXP': 0,
        'totalDistance': 0,
        'totalSessions': 0,
        'totalSteps': 0,
      });

      // ─── 2. THE GLOBAL LEADERBOARD (leaderboard/{uid}) ───
      final leaderboardRef = firestore.collection('leaderboard').doc(uid);
      batch.set(leaderboardRef, {
        'userId': uid,
        'score': 0,
        'totalDistance': 0,
        'rank': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // ─── 3. TOP-LEVEL RESEARCH SURVEYS (survey_responses/baseline_survey/submissions/{uid}) ───
      Map<String, dynamic> surveyResponses = {};
      List<String> excludedKeys = [
        'firstName', 'lastName', 'zipCode', 'state', 'city', 
        'gender', 'genderSpecify', 'ethnicity', 'race', 'education', 'raceSpecify',
        'foodTracking', 'takingMedication', 'medicationName',
        'bpAppUsage', 'bpAppType', 'additionalNotes', 'consentAgreement', 'digitalSignature'
      ];
      
      // Auto-filter: Only push actual survey answers that aren't null
      formData.forEach((key, value) {
        if (!excludedKeys.contains(key) && value != null) {
          surveyResponses[key] = value;
        }
      });

      final surveyRef = firestore
          .collection('survey_responses')
          .doc('baseline_survey')
          .collection('submissions')
          .doc(uid);

      batch.set(surveyRef, {
        'userId': uid,
        'responses': surveyResponses,
        'completedAt': FieldValue.serverTimestamp(),
      });

      // Commit the batch to Firestore
      await batch.commit();

      return uid; // Return the actual Firebase UID for downstream screens!
      
    } catch (e) {
      debugPrint("💥 Professional Onboarding Sync Error: $e");
      return null;
    }
  }
}