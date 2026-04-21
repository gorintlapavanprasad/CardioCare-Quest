import 'package:cardio_care_quest/features/dashboard/screens/main_layout.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  // ─── ADDED: High-quality Unsplash image URLs for the demo ───
  final List<Map<String, dynamic>> _pages = [
    {
      "title": "Play with Purpose",
      "body": "Complete daily quests to lower blood pressure.",
      "icon": Icons.sports_esports_rounded,
      "image": "https://images.unsplash.com/photo-1534438327276-14e5300c3a48?q=80&w=1470&auto=format&fit=crop" // Person walking dog
    },
    {
      "title": "Track Your Health",
      "body": "Monitor your progress with our dashboard.",
      "icon": Icons.insights_rounded,
      "image": "https://images.unsplash.com/photo-1505751172876-fa1923c5c528?q=80&w=1470&auto=format&fit=crop" // Medical/Health aesthetic
    },
    {
      "title": "Powering Research",
      "body": "Help researchers fight hypertension.",
      "icon": Icons.biotech_rounded,
      "image": "https://images.unsplash.com/photo-1532094349884-543bc11b234d?q=80&w=1470&auto=format&fit=crop" // Science/Lab aesthetic
    },
  ];

  Future<void> _markAsDoneAndGoHome() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('ABC_Onboarding')
            .doc('user')
            .collection(user.uid)
            .doc('flags')
            .set({
          'play_message': true,
          'completedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainLayout()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark backdrop during image loads
      body: Stack(
        children: [
          /// 🖼️ 1. FULL SCREEN BACKGROUND IMAGES
          PageView.builder(
            controller: _pageController,
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(_pages[index]["image"]),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  // ─── ADDED: Dark Gradient Overlay so text pops ───
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60), // Push down slightly
                        
                        /// ICON
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.15), // Glassmorphism circle behind icon
                          ),
                          child: Icon(
                            _pages[index]["icon"],
                            size: 90,
                            color: AppColors.activeTeal, // Keep your brand color
                          ),
                        ),
                        const SizedBox(height: 40),

                        /// TITLE (Changed to White)
                        Text(
                          _pages[index]["title"],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 20),

                        /// BODY (Changed to White/Light Grey)
                        Text(
                          _pages[index]["body"],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          /// 🔝 2. FLOATING TOP BAR (SKIP BUTTON)
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: TextButton(
                  onPressed: _markAsDoneAndGoHome,
                  child: const Text(
                    "Skip",
                    style: TextStyle(
                      color: Colors.white70, // Make visible on dark backgrounds
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),

          /// 🔽 3. FLOATING BOTTOM CONTROLS
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(30, 0, 30, 40),
                child: Row(
                  children: [
                    /// DOTS
                    Expanded(
                      child: Row(
                        children: List.generate(_pages.length, (index) {
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(right: 8),
                            height: 8,
                            width: _currentPage == index ? 28 : 8,
                            decoration: BoxDecoration(
                              color: _currentPage == index
                                  ? AppColors.activeTeal
                                  : Colors.white.withOpacity(0.4), // Lighter inactive dots
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),

                    /// ✅ BUTTON
                    SizedBox(
                      width: 130,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.activeTeal,
                          foregroundColor: Colors.white,
                          elevation: 8,
                          shadowColor: AppColors.activeTeal.withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          if (_currentPage == _pages.length - 1) {
                            _markAsDoneAndGoHome();
                          } else {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOutCubic,
                            );
                          }
                        },
                        child: Text(
                          _currentPage == _pages.length - 1 ? "START" : "NEXT",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}