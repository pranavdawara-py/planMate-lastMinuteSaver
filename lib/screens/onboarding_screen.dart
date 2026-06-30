import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../widgets/app_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _controller = PageController();
  int _currentPage = 0;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const _pages = [
    _OnboardPage(
      emoji: '⏰',
      title: 'Never Miss a Deadline',
      subtitle:
          'planMate tracks tasks, reminders, and fixed schedule blocks — so nothing slips through.',
      color: Color(0xFF7C6AF0),
    ),
    _OnboardPage(
      emoji: '🤖',
      title: 'Just Talk, AI Does the Rest',
      subtitle:
          'Describe your day in plain English. planMate\'s AI creates tasks, schedules them, and sets reminders — all from one conversation.',
      color: Color(0xFF2DD4BF),
    ),
    _OnboardPage(
      emoji: '📅',
      title: 'See Your Whole Day at a Glance',
      subtitle:
          'A beautiful timeline shows exactly where you are and what\'s coming — fixed blocks, flexible tasks, and reminder markers.',
      color: Color(0xFFF59E0B),
    ),
    _OnboardPage(
      emoji: '🔒',
      title: 'Your Data, Your Control',
      subtitle:
          'Everything is stored locally on your device first. Cloud sync is optional. We never sell your data. AI conversations go through a secure proxy — your API key is never exposed.',
      color: Color(0xFF60A5FA),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AppShell(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageColor = _pages[_currentPage].color;
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Stack(
        children: [
          // Ambient background glow that shifts with each slide
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.3),
                radius: 1.1,
                colors: [
                  pageColor.withValues(alpha: 0.18),
                  pageColor.withValues(alpha: 0.06),
                  const Color(0xFF080810),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          // Bottom corner accent glow
          Positioned(
            bottom: -60,
            left: -40,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    pageColor.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Column(
                children: [
                  // Page content
                  Expanded(
                    child: PageView.builder(
                      controller: _controller,
                      onPageChanged: (i) {
                        setState(() => _currentPage = i);
                        _fadeCtrl.reset();
                        _fadeCtrl.forward();
                      },
                      itemCount: _pages.length,
                      itemBuilder: (context, i) => _buildPage(_pages[i]),
                    ),
                  ),

                  // Bottom controls
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
                    child: Column(
                      children: [
                        // Dot indicators
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _pages.length,
                            (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _currentPage ? 24 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: i == _currentPage
                                    ? pageColor
                                    : Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Action button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  pageColor,
                                  pageColor.withValues(alpha: 0.75),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: pageColor.withValues(alpha: 0.4),
                                  blurRadius: 20,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _goNext,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                _currentPage < _pages.length - 1
                                    ? 'Next'
                                    : 'Get Started',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Skip button — LAST in Stack so it's always on top and tappable
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(_OnboardPage page) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(36, 60, 36, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container with glow
          Container(
            width: 130,
            height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: page.color.withValues(alpha: 0.1),
              border: Border.all(
                  color: page.color.withValues(alpha: 0.3), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: page.color.withValues(alpha: 0.2),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Center(
              child: Text(page.emoji,
                  style: const TextStyle(fontSize: 56)),
            ),
          ),
          const SizedBox(height: 44),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardPage {
  final String emoji;
  final String title;
  final String subtitle;
  final Color color;
  const _OnboardPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}
