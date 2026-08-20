// auth_provider.dart - the "brain" behind the sign-up questionnaire.
//
// It remembers which step you're on and every answer you've typed, and at the
// end it creates your account and saves all your answers to the cloud.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get_it/get_it.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/firestore_paths.dart';
import '../../core/services/offline_queue.dart';

// Holds the sign-up form state (current page + all answers).
class AuthProvider extends ChangeNotifier {
  int _currentStep = 0; // which page of the form we're on
  final int totalSteps = 14; // how many pages there are
  final Map<String, dynamic> _formData = {}; // every answer, keyed by question
  final bool _isSubmitting = false;

  int get currentStep => _currentStep;
  Map<String, dynamic> get formData => _formData;
  bool get isSubmitting => _isSubmitting;

  // Progress bar color: shifts through the palette as you near the last page.
  Color get progressColor {
    double t = (_currentStep + 1) / totalSteps;
    if (t < 0.25) return AppColors.viridis0;
    if (t < 0.50) return AppColors.viridis1;
    if (t < 0.75) return AppColors.viridis2;
    if (t < 0.95) return AppColors.viridis3;
    return AppColors.viridis4;
  }

  // Save one answer and refresh any screen showing it.
  void updateField(String key, dynamic value) {
    _formData[key] = value;
    debugPrint('Form Field Updated -> $key: $value');
    notifyListeners();
  }

  // Go forward one page (stops at the last page).
  void nextStep() {
    if (_currentStep < totalSteps - 1) {
      _currentStep++;
      notifyListeners();
    }
  }

  // Go back one page (stops at the first page).
  void prevStep() {
    if (_currentStep > 0) {
      _currentStep--;
      notifyListeners();
    }
  }

  // Create the account and save the profile + survey answers.
  // Returns the new user id on success, or null on failure.
  Future<String?> submitQuest() async {
    try {
      // signInAnonymously needs internet. Register participants on Wi-Fi.
      UserCredential userCredential =
          await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;
      // Short readable id shown to the participant.
      String displayId =
          'CCQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // These fields go into the profile separately, so skip them in the survey list.
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

      // Build the survey question and response lists from remaining answers.
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

      // Generate a doc id client-side so OfflineQueue can replay it correctly.
      final firestore = FirebaseFirestore.instance;
      final submissionDocId = firestore
          .collection(FirestorePaths.responses)
          .doc(FirestorePaths.baselineSurvey)
          .collection('submissions')
          .doc()
          .id;

      // Save the profile, question list, and responses as one atomic batch.
      await GetIt.instance<OfflineQueue>().enqueueBatch([
        PendingOp.set(
          '${FirestorePaths.userData}/$uid',
          {
            'uid': uid,
            'email': userCredential.user!.email ??
                'guest_${uid.substring(0, 5)}@demo.com',
            'participantId': displayId,
            'status': 'active',
            'measurementsTaken': 0,
            'distanceTraveled': 0,
            'dataPoints': [],
            'radGyration': 0,
            'createdAt': OfflineFieldValue.nowTimestamp(),
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
            'totalDistance': 0,
            'totalSessions': 0,
            'totalSteps': 0,
          },
        ),
        PendingOp.set(
          '${FirestorePaths.surveys}/${FirestorePaths.baselineSurvey}',
          {
            'questions': surveyQuestions,
            'updatedAt': OfflineFieldValue.nowTimestamp(),
          },
          merge: true,
        ),
        PendingOp.set(
          '${FirestorePaths.responses}/${FirestorePaths.baselineSurvey}/'
          'submissions/$submissionDocId',
          {
            'ID': uid,
            'responses': surveyResponses,
            'timestamp': OfflineFieldValue.nowTimestamp(),
          },
        ),
      ]);

      return uid;
    } catch (e) {
      debugPrint('Onboarding sync error: $e');
      return null;
    }
  }
}

