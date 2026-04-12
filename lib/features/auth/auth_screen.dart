import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import '../../core/theme/app_colors.dart';
import 'auth_provider.dart';
import 'create_pin_screen.dart';
import 'widgets/custom_option_button.dart';
import 'widgets/signature_pad.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Add this import
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final PageController _pageController = PageController();
  // ─── ADD THIS VARIABLE ───
  bool _isSubmitting = false;
  
  // ─── THE 35 RESEARCH PROTOCOL QUESTIONS ───
  final Map<int, String> _surveyQuestions = {
    1: "I decided to start using Cardio Care Quest because other people want me to use it.",
    2: "I would expect Cardio Care Quest to be interesting to use.",
    3: "I believe Cardio Care Quest could improve my life.",
    4: "Cardio Care Quest could help me do something important.",
    5: "I would want others to know I use Cardio Care Quest.",
    6: "I would feel bad about myself if I didn't try Cardio Care Quest.",
    7: "I think Cardio Care Quest would be enjoyable.",
    8: "I am required to use Cardio Care Quest (e.g. by my job, hospital, or family).",
    9: "Cardio Care Quest could be of value to me.",
    10: "Cardio Care Quest would be fun to use.",
    11: "Cardio Care Quest would look good to others if I use it.",
    12: "I would feel confident that I could use Cardio Care Quest effectively.",
    13: "Cardio Care Quest would be easy for me to use.",
    14: "I would feel very capable and effective at using Cardio Care Quest.",
    15: "I would feel confident in my ability to use Cardio Care Quest.",
    16: "Learning how to use Cardio Care Quest would be difficult.",
    17: "I would find the Cardio Care Quest interface and controls confusing.",
    18: "It won't be easy for me to use Cardio Care Quest.",
    19: "Cardio Care Quest would provide me with useful options and choices.",
    20: "I would be able to get Cardio Care Quest to do what I want.",
    21: "I would feel pressured by the use of Cardio Care Quest.",
    22: "Cardio Care Quest would feel intrusive.",
    23: "Cardio Care Quest would feel controlling.",
    24: "Cardio Care Quest would help me form or sustain fulfilling relationships.",
    25: "Cardio Care Quest would help me feel part of a larger community.",
    26: "Cardio Care Quest would make me feel connected to other people.",
    27: "I wouldn't feel close to other users using Cardio Care Quest.",
    28: "Cardio Care Quest wouldn't support meaningful connections to others.",
    29: "I would find using Cardio Care Quest too difficult to do regularly.",
    30: "I would only use Cardio Care Quest because I have to.",
    31: "I would find using Cardio Care Quest to track blood pressure too challenging.",
    32: "It would be easy to use Cardio Care Quest to help me remember to take my medication on time.",
    33: "I would use Cardio Care Quest to help remember my medication because other people want me to.",
    34: "I would feel guilty if I don't use Cardio Care Quest to track my blood pressure.",
    35: "Using Cardio Care Quest to remember my medication would help me feel part of a larger community."
  };

  // ─── ADD THIS CONTROLLER ───
  final SignatureController _sigController = SignatureController(
    penStrokeWidth: 3,
    penColor: AppColors.title,
  );

  @override
  void dispose() {
    _pageController.dispose();
    _sigController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final int totalSteps = authProvider.totalSteps;
    final int currentStep = authProvider.currentStep;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: AppColors.background),
        child: SafeArea(
          child: Column(
            children: [
              // ─── Segmented Progress Header ───
              _buildProgressHeader(currentStep, totalSteps),

              // ─── Main Content Card (Glassmorphism feel) ───
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: AppColors.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Column(
                      children: [
                        Expanded(
                          child: PageView(
                            controller: _pageController,
                            physics: const NeverScrollableScrollPhysics(),
                            // Generates exactly 14 pages based on the provider's total steps
                            children: List.generate(
                              totalSteps, 
                              (index) => _buildStepContent(authProvider, index + 1)
                            ),
                          ),
                        ),
                        
                        // Bottom Viridis Accent Bar
                        Container(
                          height: 4,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.viridis0,
                                AppColors.viridis1,
                                AppColors.viridis2,
                                AppColors.viridis3,
                                AppColors.viridis4,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ─── Navigation Buttons ───
              _buildNavButtons(authProvider),
            ],
          ),
        ),
      ),
    );
  }

  // ─── WIDGET BUILDERS ───

  Widget _buildProgressHeader(int current, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "STEP ${current + 1} OF $total",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: getViridisColor(current + 1, total),
                ),
              ),
              Text(
                "${((current + 1) / total * 100).round()}% COMPLETE",
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.placeholder),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Segmented Progress Bar 
          Row(
            children: List.generate(total, (index) {
              bool isPast = index < current;
              bool isCurrent = index == current;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: index == total - 1 ? 0 : 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isPast || isCurrent 
                        ? getViridisColor(index + 1, total) 
                        : AppColors.placeholder.withValues(alpha: 0.2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ─── DYNAMIC STEP RENDERER ───
  // Notice we now pass the 'step' directly from the PageView generator!
  Widget _buildStepContent(AuthProvider provider, int step) {
   switch (step) {
  case 1:
        return _buildStepWrapper("Basic Information", [
          _buildTextField(provider, "firstName", "First Name", "Enter your first name"),
          _buildTextField(provider, "lastName", "Last Name", "Enter your last name"),
          _buildTextField(provider, "zipCode", "Zip Code", "e.g. 78701", isNumber: true),
          _buildTextField(provider, "state", "State", "e.g. Texas"),
          _buildTextField(provider, "city", "City", "e.g. Austin"),
        ]);

    case 2: // NEW: PhenX & Education
      return _buildStepWrapper("Demographics", [
        const Text("Ethnicity", style: TextStyle(fontWeight: FontWeight.bold)),
        _buildRadioField(provider, "ethnicity", ["Hispanic or Latino", "Not Hispanic or Latino"]),
        const SizedBox(height: 16),
        const Text("Race", style: TextStyle(fontWeight: FontWeight.bold)),
        _buildRadioField(provider, "race", ["American Indian or Alaska Native", "Asian", "Black or African American", "Native Hawaiian or Other Pacific Islander", "White"]),
        const SizedBox(height: 16),
        const Text("Highest Education Level", style: TextStyle(fontWeight: FontWeight.bold)),
        _buildRadioField(provider, "education", ["Less than High School", "High School / GED", "Some College", "Bachelor's Degree", "Graduate Degree"]),
      ]);

    case 3: // NEW: Habits (Food/Medication)
      return _buildStepWrapper("Health Habits", [
        const Text("How often do you track your nutrition/food?", style: TextStyle(fontWeight: FontWeight.bold)),
        _buildRadioField(provider, "foodTracking", ["Daily", "Weekly", "Monthly", "Never"]),
        const SizedBox(height: 16),
        const Text("Are you currently taking Blood Pressure medication?", style: TextStyle(fontWeight: FontWeight.bold)),
        _buildRadioField(provider, "takingMedication", ["Yes", "No"]),
        if (provider.formData['takingMedication'] == 'Yes')
          _buildTextField(provider, "medicationName", "Medication Name", "e.g. Lisinopril"),
      ]);
        
      case 4:
        return _buildStepWrapper("App Management", [
          const Text("Do you currently use an app to manage your blood pressure?", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          _buildRadioField(provider, "bpAppUsage", ["Yes", "No"]),
          if (provider.formData['bpAppUsage'] == 'Yes')
            _buildTextField(provider, "bpAppType", "Which app do you use?", "e.g. MyFitnessPal, Apple Health..."),
        ]);

      // Health Survey Slider Groups
      case 5: case 6: case 7: case 8: case 9: case 10: case 11: case 12:
        return _buildSliderGroup(provider, step);

      case 13:
        return _buildStepWrapper("Additional Reflections", [
          const Text("Please share any final thoughts about your heart health journey.", style: TextStyle(color: AppColors.subtitle, fontSize: 14)),
          const SizedBox(height: 16),
          _buildTextField(provider, "additionalNotes", "Sharing more", "Your answer...", maxLines: 5),
        ]);
        
      case 14:
        return _buildStepWrapper("Consent to Participate", [
          const Text("Please read the consent form carefully, then sign below to confirm your agreement.", style: TextStyle(color: AppColors.subtitle, fontSize: 14)),
          const SizedBox(height: 24),
          
          // ─── UPDATED: Consent Text Box with Scrollbar ───
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // Room for the scrollbar
            decoration: BoxDecoration(
              color: AppColors.viridis1.withOpacity(0.04),
              border: Border.all(color: AppColors.viridis1.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(16),
            ),
            height: 200,
            child: Scrollbar(
              thumbVisibility: true, // Makes it always visible while scrolling
              thickness: 4,
              radius: const Radius.circular(10),
              child: const SingleChildScrollView(
                padding: EdgeInsets.all(8),
                child: Text(
                  "Title: CardioCare Quest: A Co-created Serious Game for High Blood Pressure Healthcare Compliance\n\n"
                  "Principal Investigator: Jared Duval, PhD; Tochukwu Ikwunne, PhD; Creaque Charles Tyler (Texas State University), PharmD\n\n"
                  "Summary of the research:\n"
                  "This is a consent form for participation in a research study. Your participation is voluntary. "
                  "You are being asked to participate in a study about creating a serious game for health (called CardioCare Quest) "
                  "that enhances treatment compliance of High Blood Pressure (HBP) for indigenous populations.\n\n"
                  "AGREEMENT TO PARTICIPATE\n"
                  "I have read (or someone has read to me) this form, and I am aware that I am being asked to participate in a research study. "
                  "I affirm that I am at least 18 years of age and voluntarily agree to participate.",
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildRadioField(provider, "consentAgreement", ["I have read and agree to the terms above"]),
          const SizedBox(height: 32),
          
          const Text("Digital Signature", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text("Please sign in the box below.", style: TextStyle(fontSize: 13, color: AppColors.subtitle)),
          const SizedBox(height: 12),
          SignaturePad(controller: _sigController, onClear: () => _sigController.clear()),
        ]);
        
      default:
        return const SizedBox.shrink();
    }
  }

// ─── SLIDER GROUP RENDERER ───
  Widget _buildSliderGroup(AuthProvider provider, int step) {
    final Map<int, List<int>> stepMap = {
      5: [1, 2, 3, 4, 5],
      6: [6, 7, 8, 9, 10],
      7: [11, 12, 13, 14, 15],
      8: [16, 17, 18, 19, 20],
      9: [21, 22, 23, 24, 25],
      10: [26, 27, 28, 29],
      11: [30, 31, 32],
      12: [33, 34, 35]
    };

    // ─── NEW: Thematic titles instead of "Form X" ───
    final Map<int, String> thematicTitles = {
      5: "Initial Thoughts",
      6: "Your Expectations",
      7: "App Confidence",
      8: "Usability",
      9: "Personal Boundaries",
      10: "Social Connection",
      11: "Daily Engagement",
      12: "Building Habits"
    };

  List<int> questionNumbers = stepMap[step] ?? [];
  String pageTitle = thematicTitles[step] ?? "Reflection";
  
  return _buildStepWrapper(pageTitle, [
    const Text(
      "Please rate how much you agree with each statement. (1 = Strongly Disagree, 7 = Strongly Agree)", 
      style: TextStyle(fontSize: 14, color: AppColors.subtitle)
    ),
    const SizedBox(height: 32),
    
    ...questionNumbers.map((qNum) {
      String fullQuestionText = _surveyQuestions[qNum] ?? "Question $qNum";
      String dbKey = fullQuestionText.endsWith('.') 
          ? fullQuestionText.substring(0, fullQuestionText.length - 1) 
          : fullQuestionText;

      return Padding(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullQuestionText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.title)
            ),
            const SizedBox(height: 24),
            
            // ─── REPLACED ViridisSlider WITH THIS ───
            _buildLikertScale(provider, dbKey), 
            // ────────────────────────────────────────
          ],
        ),
      );
    }),
  ]);
    
}

Widget _buildStepWrapper(String title, List<Widget> children) {
    return Scrollbar(
      thumbVisibility: true, // Forces the scrollbar to stay visible while scrolling
      thickness: 4,
      radius: const Radius.circular(10),
      child: SingleChildScrollView(
        // Reduce horizontal padding slightly to give the 1-7 scale more room
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 100), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 24)),
            const SizedBox(height: 24),
            ...children.map((w) => Padding(padding: const EdgeInsets.only(bottom: 16), child: w)),
            // ─── ADD THIS: Prevents content from being flush against the bottom ───
            const SizedBox(height: 60), 
          ],
        ),
      ),
    );
  }

  // ─── INPUT RENDERERS ───
 Widget _buildTextField(AuthProvider provider, String key, String label, String hint, {bool isNumber = false, int maxLines = 1}) {
    return TextField(
      onChanged: (val) => provider.updateField(key, val),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        // ─── THE FIX: Add a real border side ───
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.activeTeal, width: 2),
        ),
      ),
    );
  }

  Widget _buildRadioField(AuthProvider provider, String key, List<String> options) {
    return Column(
      children: options.map<Widget>((opt) => CustomOptionButton(
        label: opt,
        isSelected: provider.formData[key] == opt,
        onTap: () => provider.updateField(key, opt),
      )).toList(),
    );
  }

Widget _buildNavButtons(AuthProvider provider) {
  // ─── OPTIONAL: Toggle this boolean to true for the demo ───
  final bool isDemoMode = true; 

  return Padding(
    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
    child: Row(
      children: [
        if (provider.currentStep > 0)
          Expanded(
            flex: 1,
            child: TextButton.icon(
              onPressed: _isSubmitting ? null : () {
                provider.prevStep();
                _pageController.animateToPage(
                  provider.currentStep,
                  duration: const Duration(milliseconds: 400), 
                  curve: Curves.easeInOutCubic,
                );
              },
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text("BACK"),
              style: TextButton.styleFrom(foregroundColor: AppColors.placeholder),
            ),
          ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : () async {
              if (provider.currentStep < provider.totalSteps - 1) {
                provider.nextStep();
                _pageController.animateToPage(
                  provider.currentStep,
                  duration: const Duration(milliseconds: 400), 
                  curve: Curves.easeInOutCubic,
                );
              } else {
                setState(() => _isSubmitting = true);
                
                String? newId = await provider.submitQuest();
                
                if (newId != null && mounted) {

                  final prefs = await SharedPreferences.getInstance();
    await prefs.setString('participant_id', newId);
                  // ─── THE DEMO TOGGLE ───
                  if (isDemoMode) {
                    // Send directly to Dashboard for the conference
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const MainLayout()),
                    );
                  } else {
                    // Original Authentication Flow (Revertable)
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => CreatePinScreen(participantId: newId)),
                    );
                  }
                  // ───────────────────────
                } else if (mounted) {
                  setState(() => _isSubmitting = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Submission failed. Please try again."), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: _isSubmitting
                ? const SizedBox(
                    width: 24, height: 24, 
                    child: CircularProgressIndicator(color: AppColors.viridis0, strokeWidth: 3)
                  )
                : Text(provider.currentStep == provider.totalSteps - 1 ? "FINISH" : "NEXT"),
          ),
        ),
      ],
    ),
  );
}
Widget _buildLikertScale(AuthProvider provider, String key) {
    return Column(
      children: [
        Row(
          children: List.generate(7, (index) {
            int value = index + 1;
            // Use current value or default to 1 for the radio group logic
            int currentValue = provider.formData[key] ?? 0; 
            
            return Expanded(
              child: InkWell( // Making the whole column tappable is better UX
                onTap: () => provider.updateField(key, value),
                child: Column(
                  children: [
                    Radio<int>(
                      value: value,
                      groupValue: currentValue,
                      activeColor: AppColors.activeTeal,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, // Shrinks the hit area to save space
                      onChanged: (val) => provider.updateField(key, val),
                    ),
                    Text("$value", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Strongly Disagree", style: TextStyle(fontSize: 9, color: AppColors.placeholder, fontWeight: FontWeight.w600)),
              Text("Strongly Agree", style: TextStyle(fontSize: 9, color: AppColors.placeholder, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}