import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/design_system.dart';

/// Animated splash: VOICE → FARM → COMMUNITY → MARKET.
///
/// A sound wave pulses, condenses into a sprouting leaf, is joined by
/// connected farmer nodes (community), and settles into the wordmark.
/// Ends with brand + tagline + "powered by AfriTech Bridge".
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _master = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2100));
  late final AnimationController _wave = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _master.forward();
    _navigateOn();
  }

  Future<void> _navigateOn() async {
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    if (!mounted) return;
    // Router redirect decides between /auth/login and home; splash lives
    // outside the shell so we just hand over.
    context.go('/');
  }

  @override
  void dispose() {
    _wave.dispose();
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IjwiColors.greenDark,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Center(
              child: FadeTransition(
                opacity: CurvedAnimation(
                    parent: _master, curve: const Interval(0.0, 0.5)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 150,
                    height: 110,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_wave, _master]),
                      builder: (context, _) => CustomPaint(
                        painter: _VoiceLeafPainter(
                          waveT: _wave.value,
                          growT: CurvedAnimation(
                                  parent: _master,
                                  curve: const Interval(0.25, 0.75,
                                      curve: Curves.easeOutBack))
                              .value,
                          netT: CurvedAnimation(
                                  parent: _master,
                                  curve: const Interval(0.6, 1.0))
                              .value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _master, curve: const Interval(0.7, 0.95)),
                    child: const Text('IJWI RYAJYE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3)),
                  ),
                  const SizedBox(height: 6),
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _master, curve: const Interval(0.8, 1.0)),
                    child: Text('Your voice. Your farm. Your market.',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13)),
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FadeTransition(
              opacity: CurvedAnimation(
                  parent: _master, curve: const Interval(0.85, 1.0)),
              child: Text('powered by AfriTech Bridge',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.65), fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Paints the splash hero in three blended phases:
/// phase <0.4 sound-wave bars, 0.4-0.8 morphing leaf, >0.8 network dots.
class _VoiceLeafPainter extends CustomPainter {
  _VoiceLeafPainter(
      {required this.waveT, required this.growT, required this.netT});

  final double waveT;
  final double growT;
  final double netT;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.62;

    // ---- Phase 1: sound wave bars (fade out as leaf grows) ----
    if (growT < 1) {
      final alpha = (1 - growT).clamp(0.0, 1.0);
      final barPaint = Paint()
        ..color = Colors.white.withOpacity(alpha)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5;
      const count = 7;
      for (var i = 0; i < count; i++) {
        final dx = cx + (i - count ~/ 2) * 16.0;
        final h =
            12 + 34 * (0.5 + 0.5 * math.sin(waveT * 2 * math.pi + i * 1.1));
        final hh = h * (1 - growT * 0.55);
        canvas.drawLine(
            Offset(dx, cy - hh / 2), Offset(dx, cy + hh / 2), barPaint);
      }
    }

    // ---- Phase 2: sprouting leaf ----
    if (growT > 0) {
      final leafPaint = Paint()..color = const Color(0xFF9FE0B5);
      final stemPaint = Paint()
        ..color = const Color(0xFFCFF2DC)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final g = Curves.easeOutBack.transform(growT.clamp(0.0, 1.0));
      final path = Path()
        ..moveTo(cx, cy)
        ..quadraticBezierTo(cx - 34 * g, cy - 30 * g, cx, cy - 62 * g)
        ..quadraticBezierTo(cx + 34 * g, cy - 30 * g, cx, cy);
      canvas.drawPath(path, leafPaint);
      canvas.drawLine(Offset(cx, cy), Offset(cx, cy + 20 * g), stemPaint);
    }

    // ---- Phase 3: community network dots ----
    if (netT > 0) {
      final dotPaint = Paint()
        ..color = Colors.white.withOpacity(0.9 * netT);
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(0.35 * netT)
        ..strokeWidth = 1.2;
      const pts = [
        Offset(-58, -46),
        Offset(56, -50),
        Offset(-64, 10),
        Offset(66, 6),
        Offset(-30, 30),
        Offset(36, 32),
      ];
      final origin = Offset(cx, cy - 40);
      for (final p in pts) {
        final o = origin + p * netT;
        canvas.drawCircle(o, 3.2, dotPaint);
        canvas.drawLine(origin, o, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceLeafPainter old) =>
      old.waveT != waveT || old.growT != growT || old.netT != netT;
}
