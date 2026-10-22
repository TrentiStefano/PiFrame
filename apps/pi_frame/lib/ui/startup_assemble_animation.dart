import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pi_frame_theme/pi_frame_theme.dart';
import 'startup_audio.dart';

class StartupAssembleOverlay extends StatefulWidget {
  final Widget child;
  final bool autoStart;
  final VoidCallback? onAnimationComplete;

  const StartupAssembleOverlay({
    super.key,
    required this.child,
    this.autoStart = true,
    this.onAnimationComplete,
  });

  @override
  State<StartupAssembleOverlay> createState() => _StartupAssembleOverlayState();
}

class _StartupAssembleOverlayState extends State<StartupAssembleOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _dismissed = false;
  bool _ciakPlayed = false;
  bool _humPlayed = false;

  @override
  void initState() {
    super.initState();
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    _controller = AnimationController(
      vsync: this,
      duration: isTest ? const Duration(milliseconds: 50) : const Duration(milliseconds: 1400),
    );

    _controller.addListener(_onProgressChanged);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finish();
      }
    });

    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (MediaQuery.disableAnimationsOf(context) || isTest) {
          _finish();
        } else {
          _controller.forward();
        }
      });
    }
  }

  void _onProgressChanged() {
    final v = _controller.value;
    // Ciak sound plays exactly at framing lock (~0.52)
    if (v >= 0.52 && !_ciakPlayed) {
      _ciakPlayed = true;
      StartupAudio.playCiak();
    }
    // Hum sound plays softly during radiant glow phase (~0.68)
    if (v >= 0.68 && !_humPlayed) {
      _humPlayed = true;
      StartupAudio.playHum();
    }
  }

  void _finish() {
    if (!mounted || _dismissed) return;
    setState(() {
      _dismissed = true;
    });
    widget.onAnimationComplete?.call();
  }

  @override
  void dispose() {
    _controller.removeListener(_onProgressChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) {
      return widget.child;
    }

    final tokens = context.tokens;

    return Stack(
      fit: StackFit.expand,
      children: [
        // The real application running behind
        widget.child,

        // Startup Assemble Splash Animation Overlay
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;

            // Fade out overlay from t = 0.85 to 1.0
            final overlayOpacity = (t >= 0.85)
                ? (1.0 - ((t - 0.85) / 0.15)).clamp(0.0, 1.0)
                : 1.0;

            if (overlayOpacity <= 0) {
              return const SizedBox.shrink();
            }

            return Opacity(
              opacity: overlayOpacity,
              child: Listener(
                onPointerDown: (_) => _finish(),
                child: Focus(
                  canRequestFocus: false,
                  onKeyEvent: (_, __) {
                    _finish();
                    return KeyEventResult.ignored;
                  },
                  child: Container(
                    key: const ValueKey('startup-assemble-overlay'),
                    color: tokens.background,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glow and Icon Stage
                          CustomPaint(
                            size: const Size(140, 140),
                            painter: _AssemblePainter(
                              progress: t,
                              tokens: tokens,
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Subtle brand title fading in
                          Opacity(
                            opacity: (t < 0.60) ? 0.0 : ((t - 0.60) / 0.25).clamp(0.0, 1.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'PIFRAME',
                                  style: TextStyle(
                                    color: tokens.textPrimary,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 4.0,
                                    fontFamily: tokens.headingFontFamily,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'PRECISION AGENT DESKTOP',
                                  style: TextStyle(
                                    color: tokens.textMuted,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2.2,
                                    fontFamily: tokens.monoFontFamily,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AssemblePainter extends CustomPainter {
  final double progress;
  final FrameTokens tokens;

  _AssemblePainter({
    required this.progress,
    required this.tokens,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // Phase 1: Logo pieces coming together (t: 0.0 -> 0.48)
    // Phase 2: Frame snaps down and frames logo (t: 0.48 -> 0.65) with Ciak impact
    // Phase 3: Final hum and radiant glow (t: 0.65 -> 1.0)

    final scaleFactor = size.width / 32.0;
    canvas.scale(scaleFactor, scaleFactor);

    // 1. Radiant glow in Phase 3
    if (progress > 0.60) {
      final glowPhase = ((progress - 0.60) / 0.40).clamp(0.0, 1.0);
      final glowRadius = 14.0 + 10.0 * glowPhase;
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            tokens.accent.withValues(alpha: 0.25 * (1.0 - glowPhase * 0.4)),
            tokens.accent.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: glowRadius));
      canvas.drawCircle(Offset.zero, glowRadius, glowPaint);
    }

    // 2. Inner background surface (appears at framing lock)
    if (progress >= 0.48) {
      final surfacePhase = Curves.easeOutBack.transform(
        ((progress - 0.48) / 0.16).clamp(0.0, 1.0),
      );
      final surfaceRRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 25.6 * surfacePhase, height: 25.6 * surfacePhase),
        Radius.circular(5.5 * surfacePhase),
      );
      canvas.drawRRect(surfaceRRect, Paint()..color = tokens.surface);
    }

    // 3. Pi Logo Pieces assembling
    // Origin is at center (0, 0), original 32x32 was centered at (16, 16)
    // Offset relative to (16, 16):
    const partOffsets = [
      Rect.fromLTWH(9.5 - 16, 9.5 - 16, 3.25, 13.0), // P stem
      Rect.fromLTWH(12.75 - 16, 9.5 - 16, 6.5, 3.25), // P top bar
      Rect.fromLTWH(16.0 - 16, 12.75 - 16, 3.25, 3.25), // P right wall
      Rect.fromLTWH(12.75 - 16, 16.0 - 16, 3.25, 3.25), // P bottom loop
      Rect.fromLTWH(19.25 - 16, 16.0 - 16, 3.25, 6.5), // i block
    ];

    final partColors = [
      tokens.accent,
      tokens.danger,
      tokens.danger,
      tokens.danger,
      tokens.warning,
    ];

    // Flying trajectories for the assemble phase
    const flyDirections = [
      Offset(-18, -4), // stem flies from left
      Offset(2, -18), // top bar drops from top
      Offset(18, -2), // right wall from right
      Offset(14, 14), // bottom loop from bottom right
      Offset(0, 18), // i block from bottom
    ];

    for (var i = 0; i < partOffsets.length; i++) {
      // Staggered arrival between 0.0 and 0.48
      final startT = i * 0.06;
      final pieceT = Curves.easeOutBack.transform(
        ((progress - startT) / 0.36).clamp(0.0, 1.0),
      );

      final flyOffset = flyDirections[i] * (1.0 - pieceT);
      final currentRect = partOffsets[i].shift(flyOffset);

      final alpha = (0.2 + 0.8 * pieceT).clamp(0.0, 1.0);
      final paint = Paint()..color = partColors[i].withValues(alpha: alpha);
      canvas.drawRect(currentRect, paint);
    }

    // 4. The Frame "Framing" the Logo (Phase 2: 0.48 -> 0.65)
    if (progress >= 0.45) {
      final frameT = ((progress - 0.45) / 0.16).clamp(0.0, 1.0);
      // Framing snap: frame zooms down from 1.7x to 1.0x with overshoot/bounce
      final frameScale = 1.0 + (1.0 - Curves.easeOutBack.transform(frameT)) * 0.7;

      canvas.save();
      canvas.scale(frameScale, frameScale);

      final frameRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: 28, height: 28),
        const Radius.circular(7),
      );

      final frameAlpha = (0.3 + 0.7 * frameT).clamp(0.0, 1.0);
      final framePaint = Paint()
        ..color = tokens.borderStrong.withValues(alpha: frameAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawRRect(frameRect, framePaint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AssemblePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tokens != tokens;
}
