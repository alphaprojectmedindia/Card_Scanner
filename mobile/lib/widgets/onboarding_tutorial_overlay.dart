import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Data model representing a single step in the interactive onboarding tutorial.
class OnboardingStepData {
  final int stepNumber; // 1 to 11
  final String heading;
  final String description;
  final GlobalKey? targetKey;
  final IconData? icon;

  const OnboardingStepData({
    required this.stepNumber,
    required this.heading,
    required this.description,
    this.targetKey,
    this.icon,
  });
}

/// Interactive guided tutorial overlay for Digital Share.
///
/// Features:
/// - Semi-transparent dark background with dynamic cutout around target element.
/// - Prominent vibrant blue border highlight with rounded corners and soft glow.
/// - Information popup with rounded corners, shadow, step counter (e.g. 1 / 6),
///   heading, explanatory text, and optional connection pointer.
/// - Horizontal navigation button bar:
///   - Steps 1–5: [ Previous ]  [ Next ]  [ End Tour ]
///   - Step 6:    [ Previous ]  [ Finish Tour ]
/// - Full responsive layout for mobile, tablet, and desktop viewports.
class OnboardingTutorialOverlay extends StatefulWidget {
  final List<OnboardingStepData> steps;
  final int initialStep;
  final VoidCallback onFinish;
  final VoidCallback onEndTour;
  final void Function(int newStep)? onStepChanged;
  final bool alwaysShowEndTour;

  const OnboardingTutorialOverlay({
    super.key,
    required this.steps,
    this.initialStep = 0,
    required this.onFinish,
    required this.onEndTour,
    this.onStepChanged,
    this.alwaysShowEndTour = false,
  });

  @override
  State<OnboardingTutorialOverlay> createState() => _OnboardingTutorialOverlayState();
}

class _OnboardingTutorialOverlayState extends State<OnboardingTutorialOverlay> {
  late int _currentStep;
  Rect? _targetRect;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    _currentStep = widget.initialStep.clamp(0, widget.steps.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveTargetRect();
    });
  }

  void _resolveTargetRect() {
    if (!mounted || widget.steps.isEmpty) return;

    final step = widget.steps[_currentStep];
    final key = step.targetKey;

    if (key == null) {
      setState(() {
        _targetRect = null;
        _isTransitioning = false;
      });
      return;
    }

    final targetContext = key.currentContext;

    if (targetContext != null) {
      // If the target is in a scrollable, ensure it is brought smoothly into view
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      ).then((_) {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _measureTarget(key);
        });
      }).catchError((_) {
        if (!mounted) return;
        _measureTarget(key);
      });
    } else {
      // Fallback: If target context is not available yet, retry next frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (key.currentContext != null) {
          _measureTarget(key);
        } else {
          setState(() {
            _targetRect = null;
            _isTransitioning = false;
          });
        }
      });
    }
  }

  void _measureTarget(GlobalKey key) {
    try {
      final ctx = key.currentContext;
      if (ctx == null) return;
      final targetRenderBox = ctx.findRenderObject() as RenderBox?;
      final overlayRenderBox = context.findRenderObject() as RenderBox?;
      if (targetRenderBox != null &&
          targetRenderBox.hasSize &&
          overlayRenderBox != null &&
          overlayRenderBox.hasSize) {
        // Convert global target coordinates to local coordinates of the overlay container
        final globalPos = targetRenderBox.localToGlobal(Offset.zero);
        final localPos = overlayRenderBox.globalToLocal(globalPos);
        if (mounted) {
          setState(() {
            _targetRect = localPos & targetRenderBox.size;
            _isTransitioning = false;
          });
        }
      }
    } catch (_) {}
  }

  void _goToNextStep() {
    if (_isTransitioning) return;
    if (_currentStep < widget.steps.length - 1) {
      setState(() {
        _isTransitioning = true;
        _targetRect = null; // Clear previous target rect during transition
        _currentStep++;
      });
      widget.onStepChanged?.call(_currentStep);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolveTargetRect();
        Future.delayed(const Duration(milliseconds: 350), () {
          if (mounted && _isTransitioning) setState(() => _isTransitioning = false);
        });
      });
    } else {
      widget.onFinish();
    }
  }

  void _goToPreviousStep() {
    if (_isTransitioning || _currentStep <= 0) return;
    setState(() {
      _isTransitioning = true;
      _targetRect = null; // Clear previous target rect during transition
      _currentStep--;
    });
    widget.onStepChanged?.call(_currentStep);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveTargetRect();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _isTransitioning) setState(() => _isTransitioning = false);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];
    final isFinalStep = _currentStep == widget.steps.length - 1;
    final isFirstStep = _currentStep == 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final overlaySize = Size(constraints.maxWidth, constraints.maxHeight);

        return Material(
          color: Colors.transparent,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Semi-transparent dark overlay with target cutout
              CustomPaint(
                size: overlaySize,
                painter: _TutorialOverlayPainter(
                  targetRect: _targetRect,
                  highlightColor: const Color(0xFF1E5BB0),
                  overlayColor: Colors.black.withValues(alpha: 0.72),
                ),
              ),

              // 2. Tutorial information popup
              _buildPopup(context, step, isFirstStep, isFinalStep, overlaySize),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPopup(
    BuildContext context,
    OnboardingStepData step,
    bool isFirstStep,
    bool isFinalStep,
    Size overlaySize,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate smart vertical positioning
    bool placeAbove = false;
    double? top;
    double? bottom;

    if (_targetRect != null) {
      final targetCenterY = _targetRect!.center.dy;
      final spaceAbove = _targetRect!.top;
      final spaceBelow = overlaySize.height - _targetRect!.bottom;

      if (spaceBelow < 250 && spaceAbove > spaceBelow) {
        placeAbove = true;
      } else if (spaceAbove < 250 && spaceBelow > spaceAbove) {
        placeAbove = false;
      } else {
        placeAbove = targetCenterY > overlaySize.height * 0.45;
      }

      if (placeAbove) {
        final distanceFromBottom = overlaySize.height - _targetRect!.top;
        bottom = math.max(16.0, distanceFromBottom + 14);
      } else {
        top = math.max(16.0, _targetRect!.bottom + 14);
      }
    } else {
      top = math.max(20.0, (overlaySize.height - 240) / 2);
    }

    return Positioned(
      top: placeAbove ? null : top,
      bottom: placeAbove ? bottom : null,
      left: 20,
      right: 20,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Connecting pointer/arrow pointing to highlighted element
          if (_targetRect != null && !placeAbove)
            CustomPaint(
              size: const Size(20, 10),
              painter: _TrianglePainter(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                pointUp: true,
              ),
            ),

          Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(
                color: const Color(0xFF1E5BB0).withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top row: Step counter & step icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E5BB0).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFF1E5BB0).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        '${step.stepNumber} / ${widget.steps.length}',
                        key: const Key('tutorial_step_counter'),
                        style: const TextStyle(
                          color: Color(0xFF1E5BB0),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (isFinalStep)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF10B981),
                          size: 20,
                        ),
                      )
                    else if (step.icon != null)
                      Icon(
                        step.icon,
                        color: const Color(0xFF1E5BB0),
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // Heading
                Text(
                  step.heading,
                  key: const Key('tutorial_heading'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),

                // Description
                Text(
                  step.description,
                  key: const Key('tutorial_description'),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    color: isDark ? Colors.grey.shade300 : const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 20),

                // CRITICAL REQUIREMENT: Horizontal navigation buttons in the SAME row!
                // Steps 1–5: [ Previous ]  [ Next ]  [ End Tour ]
                // Step 6:    [ Previous ]  [ Finish Tour ]
                Row(
                  key: const Key('tutorial_navigation_bar'),
                  children: [
                    // Previous Button
                    Expanded(
                      flex: 3,
                      child: OutlinedButton(
                        key: const Key('tutorial_previous_button'),
                        onPressed: isFirstStep ? null : _goToPreviousStep,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          side: BorderSide(
                            color: isFirstStep
                                ? Colors.grey.shade400.withValues(alpha: 0.3)
                                : const Color(0xFF1E5BB0).withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          'Previous',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isFirstStep
                                ? Colors.grey.shade500
                                : const Color(0xFF1E5BB0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Next / Finish Tour Button
                    Expanded(
                      flex: isFinalStep ? 5 : 3,
                      child: FilledButton.icon(
                        key: isFinalStep
                            ? const Key('tutorial_finish_button')
                            : const Key('tutorial_next_button'),
                        onPressed: _goToNextStep,
                        style: FilledButton.styleFrom(
                          backgroundColor: isFinalStep
                              ? const Color(0xFF10B981)
                              : const Color(0xFF1E5BB0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: isFinalStep
                            ? const Icon(Icons.check_rounded, size: 16)
                            : const SizedBox.shrink(),
                        label: Text(
                          isFinalStep ? 'Finish Tour' : 'Next',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    // End Tour Button (Directly beside Next on steps 1–5, or always if alwaysShowEndTour is true)
                    if (!isFinalStep || widget.alwaysShowEndTour) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextButton(
                          key: const Key('tutorial_end_tour_button'),
                          onPressed: widget.onEndTour,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            foregroundColor: Colors.red.shade600,
                          ),
                          child: const Text(
                            'End Tour',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Connecting pointer/arrow pointing to highlighted element when placed above
          if (_targetRect != null && placeAbove)
            CustomPaint(
              size: const Size(20, 10),
              painter: _TrianglePainter(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                pointUp: false,
              ),
            ),
        ],
      ),
        ),
      ),
    );
  }
}

/// Custom painter that punches a transparent rounded cutout in the dark overlay
/// and renders a prominent blue border highlight around the targeted element.
class _TutorialOverlayPainter extends CustomPainter {
  final Rect? targetRect;
  final Color highlightColor;
  final Color overlayColor;

  _TutorialOverlayPainter({
    required this.targetRect,
    required this.highlightColor,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()..color = overlayColor;

    if (targetRect == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), backgroundPaint);
      return;
    }

    // Expand target rect with a small padding margin for aesthetics
    final paddedRect = targetRect!.inflate(6);
    final rrect = RRect.fromRectAndRadius(paddedRect, const Radius.circular(12));

    // Combine screen path and target cutout path
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()..addRRect(rrect);
    final transparentPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    canvas.drawPath(transparentPath, backgroundPaint);

    // Draw prominent blue border around highlighted target
    final borderPaint = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2;

    canvas.drawRRect(rrect, borderPaint);

    // Soft outer glow around the highlight
    final glowPaint = Paint()
      ..color = highlightColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    canvas.drawRRect(rrect, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _TutorialOverlayPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.overlayColor != overlayColor;
  }
}

/// Small triangle pointer connecting the popup card to the target element.
class _TrianglePainter extends CustomPainter {
  final Color color;
  final bool pointUp;

  _TrianglePainter({required this.color, required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointUp) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointUp != pointUp;
  }
}
