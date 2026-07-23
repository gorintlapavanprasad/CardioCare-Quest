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

// Holds the sign-up state (current step + answers) and shares it with screens.
class AuthProvider extends ChangeNotifier {
  int _currentStep = 0; // which page of the form we're on
  final int totalSteps = 14; // how many pages there are
  final Map<String, dynamic> _formData = {}; // every answer, keyed by question
  final bool _isSubmitting = false;

  int get currentStep => _currentStep;
  Map<String, dynamic> get formData => _formData;
  bool get isSubmitting => _isSubmitting;

  // The progress bar colour, shifting through the palette as you near the end.
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

  // Finish sign-up: make the account, then save the profile + survey answers.
  // Returns the new user id on success, or null if something went wrong.
  Future<String?> submitQuest() async {
    try {
      // signInAnonymously requires network; without an internet connection
      // Firebase Auth cannot mint a new UID. We let it throw - caller decides
      // how to surface that to the participant. (Workshop guidance: register
      // participants while connected to the registration-table Wi-Fi.)
      UserCredential userCredential =
          await FirebaseAuth.instance.signInAnonymously();
      String uid = userCredential.user!.uid;
      // A short, friendly id shown to the participant (built from the clock).
      String displayId =
          'CCQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

      // These answers go into their own profile fields below, so we keep them
      // OUT of the generic survey list to avoid saving them twice.
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

      // Turn the leftover answers into two lists: the questions, and the
      // matching responses. (Skips the profile fields excluded above.)
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

      // Auto-id for the submission doc; generated client-side so OfflineQueue
      // can replay deterministically.
      final firestore = FirebaseFirestore.instance;
      final submissionDocId = firestore
          .collection(FirestorePaths.responses)
          .doc(FirestorePaths.baselineSurvey)
          .collection('submissions')
          .doc()
          .id;

      // Save three things together (all save, or none): the user profile,
      // the survey question list, and this person's survey answers.
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
            'points': 0,
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
      // Something failed (often no internet for the sign-in). Tell the caller.
      debugPrint('Onboarding sync error: $e');
      return null;
    }
  }
}

