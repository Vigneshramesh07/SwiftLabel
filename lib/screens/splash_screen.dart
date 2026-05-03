// lib/screens/splash_screen.dart
//
// SwiftLabel Splash Screen
// - Shows real logo image + animations for ~2.5s
// - Checks Supabase session → Dashboard (logged in) or EmailScreen (not)
//
// ── SETUP ─────────────────────────────────────────────────────────────────
// 1. Copy your logo image to:  assets/images/swiftlabel_logo.png
// 2. Add to pubspec.yaml under flutter → assets:
//      - assets/images/swiftlabel_logo.png

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'email_screen.dart';
import 'dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  late AnimationController _logoCtrl;
  late AnimationController _textCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _shimmerCtrl;
  late AnimationController _floatCtrl;

  late Animation<double>  _logoScale;
  late Animation<double>  _logoOpacity;
  late Animation<Offset>  _logoSlide;
  late Animation<double>  _textOpacity;
  late Animation<Offset>  _textSlide;
  late Animation<double>  _pulse;
  late Animation<double>  _shimmer;
  late Animation<double>  _float;

  @override
  void initState() {
    super.initState();

    // ── Logo: scale + fade + slide up ─────────────────────────────
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.65, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl,
            curve: const Interval(0.0, 0.45, curve: Curves.easeOut)));
    _logoSlide = Tween<Offset>(
        begin: const Offset(0, 0.25), end: Offset.zero).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic));

    // ── Text: fade + slide up ────────────────────────────────────
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(
        begin: const Offset(0, 0.35), end: Offset.zero).animate(
        CurvedAnimation(parent: _textCtrl, curve: Curves.easeOutCubic));

    // ── Subtle pulse glow behind logo ────────────────────────────
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // ── Shimmer on tagline ────────────────────────────────────────
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
    _shimmer = Tween<double>(begin: -2.0, end: 2.0).animate(
        CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut));

    // ── Logo gentle float up/down ─────────────────────────────────
    _floatCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _float = Tween<double>(begin: -6.0, end: 6.0).animate(
        CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _textCtrl.forward();

    // Total splash time ~2.5s
    await Future.delayed(const Duration(milliseconds: 1750));
    if (!mounted) return;
    _navigate();
  }

  void _navigate() {
    final session = Supabase.instance.client.auth.currentSession;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      pageBuilder: (_, __, ___) =>
      session != null ? const DashboardScreen() : const EmailScreen(),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 500),
    ));
  }

  @override
  void dispose() {
    _logoCtrl.dispose();   _textCtrl.dispose();
    _pulseCtrl.dispose();  _shimmerCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        width: double.infinity, height: double.infinity,
        // Deep navy gradient matching logo style
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF05101F), Color(0xFF0A1E3D), Color(0xFF071526)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(children: [

          // ── Background particles ─────────────────────────────────
          ...List.generate(14, (i) => _FloatingParticle(index: i)),

          // ── Main content ─────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Logo image with animations ───────────────────
                AnimatedBuilder(
                  animation: Listenable.merge(
                      [_logoCtrl, _pulseCtrl, _floatCtrl]),
                  builder: (_, __) => SlideTransition(
                    position: _logoSlide,
                    child: FadeTransition(
                      opacity: _logoOpacity,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Transform.translate(
                          // gentle float
                          offset: Offset(0, _float.value),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer glow ring (pulsing)
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, __) => Container(
                                  width: sw * 0.58 * _pulse.value,
                                  height: sw * 0.58 * _pulse.value,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF1565C0)
                                            .withOpacity(0.25 * _pulse.value),
                                        blurRadius: 60,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // White circle card behind logo
                              Container(
                                width:  sw * 0.50,
                                height: sw * 0.50,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1565C0)
                                          .withOpacity(0.3),
                                      blurRadius: 40,
                                      offset: const Offset(0, 8),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                              ),

                              ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width:  sw * 0.46,
                                  height: sw * 0.46,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 36),

                // ── "SwiftLabel" text + tagline ──────────────────
                Center(
                  child: AnimatedBuilder(
                    animation: _textCtrl,
                    builder: (_, __) => SlideTransition(
                      position: _textSlide,
                      child: FadeTransition(
                        opacity: _textOpacity,
                        child: Column(children: [

                          // Wordmark
                          RichText(
                            text: const TextSpan(children: [
                              TextSpan(text: 'Swift', style: TextStyle(
                                fontFamily: 'Syne', fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -1.0,
                              )),
                              TextSpan(text: 'Label', style: TextStyle(
                                fontFamily: 'Syne', fontSize: 40,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF4DA6FF),
                                letterSpacing: -1.0,
                              )),
                            ]),
                          ),

                          const SizedBox(height: 10),

                          // Shimmer tagline
                          AnimatedBuilder(
                            animation: _shimmerCtrl,
                            builder: (_, __) => ShaderMask(
                              shaderCallback: (bounds) => LinearGradient(
                                colors: const [
                                  Color(0xFF6FA8CC),
                                  Color(0xFFE8F4FF),
                                  Color(0xFF6FA8CC),
                                ],
                                stops: const [0.0, 0.5, 1.0],
                                begin: Alignment(_shimmer.value - 1, 0),
                                end: Alignment(_shimmer.value + 1, 0),
                              ).createShader(bounds),
                              child: const Text(
                                'Ship smarter. Track faster.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // ── Loading dots ─────────────────────────────────
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (_, __) => FadeTransition(
                    opacity: _textOpacity,
                    child: const _LoadingDots(),
                  ),
                ),

                const SizedBox(height: 48),

                // ── Bottom tagline ────────────────────────────────
                AnimatedBuilder(
                  animation: _textCtrl,
                  builder: (_, __) => FadeTransition(
                    opacity: _textOpacity,
                    child: const Padding(
                      padding: EdgeInsets.only(bottom: 28),
                      child: Text(
                        'UK Parcel Shipping Made Simple',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF3D5A7A),
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// =============================================================================
// Loading dots
// =============================================================================

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();
  @override State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }
  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = ((_ctrl.value - i / 3.0) % 1.0 + 1.0) % 1.0;
        final opacity = (math.sin(t * math.pi)).clamp(0.2, 1.0);
        final scale   = 0.7 + 0.3 * math.sin(t * math.pi);
        return Transform.scale(
          scale: scale,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 5),
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4DA6FF).withOpacity(opacity),
            ),
          ),
        );
      }),
    ),
  );
}

// =============================================================================
// Floating background particles
// =============================================================================

class _FloatingParticle extends StatefulWidget {
  final int index;
  const _FloatingParticle({required this.index});
  @override State<_FloatingParticle> createState() => _FloatingParticleState();
}

class _FloatingParticleState extends State<_FloatingParticle>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late double _x, _y, _size, _opacity;

  @override
  void initState() {
    super.initState();
    final rng  = math.Random(widget.index * 53 + 7);
    _x       = rng.nextDouble();
    _y       = rng.nextDouble();
    _size    = 1.5 + rng.nextDouble() * 3.5;
    _opacity = 0.05 + rng.nextDouble() * 0.12;
    _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 2000 + rng.nextInt(2000)))
      ..repeat(reverse: true);
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Positioned(
        left: _x * sz.width,
        top:  _y * sz.height + _ctrl.value * 18 - 9,
        child: Container(
          width: _size, height: _size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4DA6FF)
                .withOpacity(_opacity * (0.6 + _ctrl.value * 0.4)),
          ),
        ),
      ),
    );
  }
}