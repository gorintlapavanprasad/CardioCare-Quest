import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';

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
    debugPrint('Form Field Updated -> $key: $value');
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

  Future<String?> submitQuest() async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;
      String displayId = 'CCQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();

      final userRef = firestore.collection(FirestorePaths.userData).doc(uid);
      batch.set(userRef, {
        'uid': uid,
        'email': userCredential.user!.email ?? 'guest_${uid.substring(0, 5)}@demo.com',
        'participantId': displayId,
        'status': 'active',
        'measurementsTaken': 0,
        'distanceTraveled': 0,
        'dataPoints': [],
        'radGyration': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'basicInfo': {
          'firstName': formData['firstName'] ?? 'Explorer',
          'lastName': formData['lastName'] ?? '',
          'zipCode': formData['zipCode'] ?? '',
          'state': formData['state'] ?? '',
          'city': formData['city'] ?? '',
        },
        'demographics': {
          'gender': formData['gender'],
          'ethnicity': formData['ethnicity'],
          'race': formData['race'],
          'education': formData['education'],
          'foodTracking': formData['foodTracking'],
          'takingMedication': formData['takingMedication'],
        },
        'points': 0,
        'totalDistance': 0,
        'totalSessions': 0,
        'totalSteps': 0,
      });

      final excludedKeys = [
        'firstName',
        'lastName',
        'zipCode',
        'state',
        'city',
        'gender',
        'genderSpecify',
        'ethnicity',
        'race',
        'education',
        'raceSpecify',
        'foodTracking',
        'takingMedication',
        'medicationName',
        'bpAppUsage',
        'bpAppType',
        'additionalNotes',
        'consentAgreement',
        'digitalSignature',
      ];

      final surveyQuestions = <Map<String, dynamic>>[];
      final surveyResponses = <Map<String, dynamic>>[];
      formData.forEach((key, value) {
        if (!excludedKeys.contains(key) && value != null) {
          surveyQuestions.add({
            'text': key,
            'mandatory': false,
            'choices': [],
          });
          surveyResponses.add({
            'question': key,
            'answer': value,
          });
        }
      });

      final surveyDocRef = firestore.collection(FirestorePaths.surveys).doc(FirestorePaths.baselineSurvey);
      batch.set(surveyDocRef, {
        'questions': surveyQuestions,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final surveyResponseRef = firestore
          .collection(FirestorePaths.responses)
          .doc(FirestorePaths.baselineSurvey)
          .collection('submissions')
          .doc();

      batch.set(surveyResponseRef, {
        'ID': uid,
        'responses': surveyResponses,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return uid;
    } catch (e) {
      debugPrint('Onboarding sync error: $e');
      return null;
    }
  }
}

