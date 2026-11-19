import 'dart:math';
import 'package:flutter/material.dart';
import '../../../services/card_geometry_service.dart';

/// Professional landscape business-card viewfinder guide overlay for physical card camera scanning.
///
/// Features:
/// - Exact landscape business-card aspect ratio (1.75:1)
/// - Responsive layout with zero overflow on any screen size
/// - Darkened semi-transparent mask outside the frame
/// - Clear, unobstructed interior for camera preview
/// - Rounded corner guides with vibrant accent coloring
/// - Center card watermark
/// - Real-time guidance status indicators
/// - Tactile manual shutter button
/// - Side indicator (Front / Back)
/// - Normalised viewfinder coordinates export for CardGeometryService
class BusinessCardCameraOverlay extends StatelessWidget {
  /// The active guidance state message (e.g. 'Ready to scan', 'Hold steady', 'Move closer').
  final String guidanceMessage;

  /// Whether the card is currently aligned and ready for capture.
  final bool isReady;

  /// Side being captured ('front' or 'back').
  final String sideName;

  /// Whether the device torch / flash is active.
  final bool isTorchOn;

  /// Whether capture is currently enabled (e.g. camera initialized and not busy).
  final bool isCaptureEnabled;

  /// Called when the user presses the manual capture shutter button.
  final VoidCallback onCapture;

  /// Called when the user taps the cancel / back button.
  final VoidCallback onCancel;

  /// Called when the user toggles the torch.
  final VoidCallback onToggleTorch;

  /// Called when the user selects the gallery import option.
  final VoidCallback onPickGallery;

  /// Called when the user toggles front/back side.
  final VoidCallback? onToggleSide;

  /// Callback delivering the normalized viewfinder ROI coordinates relative to the preview.
  final ValueChanged<ViewfinderNormalizedRect>? onViewfinderRectChanged;

  /// Whether real-time automatic detection and capture is active.
  final bool isAutoCapture;

  /// Callback to toggle between automatic and manual capture.
  final VoidCallback? onToggleAutoCapture;

  /// Detected card boundary rectangle in screen coordinates (if any).
  final Rect? detectedCardRect;

  /// Detected 4-corner boundary polygon in screen coordinates (Adobe Scan / MS Lens style).
  final List<Offset>? detectedPolygon;

  /// Detection state machine status.
  final CardDetectionState detectionState;

  /// Optional callback to cycle / switch camera lens direction where supported.
  final VoidCallback? onSwitchCamera;

  /// Progress towards automatic capture completion (0.0 to 1.0).
  final double autoCaptureProgress;

  /// Whether shutter flash animation is currently active.
  final bool isFlashing;

  const BusinessCardCameraOverlay({
    super.key,
    required this.guidanceMessage,
    this.isReady = false,
    this.sideName = 'FRONT',
    this.isTorchOn = false,
    this.isCaptureEnabled = true,
    this.isAutoCapture = true,
    this.onToggleAutoCapture,
    this.detectedCardRect,
    this.detectedPolygon,
    this.detectionState = CardDetectionState.searching,
    this.onSwitchCamera,
    this.autoCaptureProgress = 0.0,
    this.isFlashing = false,
    required this.onCapture,
    required this.onCancel,
    required this.onToggleTorch,
    required this.onPickGallery,
    this.onToggleSide,
    this.onViewfinderRectChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;

        // Standard landscape business card aspect ratio: 3.5" x 2.0" = 1.75:1
        const cardAspect = 1.75;

        // Viewfinder width: 86% of screen width, clamped between 260px and 420px
        final frameW = (screenW * 0.86).clamp(240.0, 420.0);
        final frameH = frameW / cardAspect;

        // Center vertically with slight top bias (0.42) for comfortable camera posture
        final frameLeft = (screenW - frameW) / 2.0;
        final frameTop = max(110.0, (screenH - frameH) * 0.40);
        final frameRect = Rect.fromLTWH(frameLeft, frameTop, frameW, frameH);

        // Notify geometry service of normalized coordinates
        if (onViewfinderRectChanged != null && screenW > 0 && screenH > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            onViewfinderRectChanged!(ViewfinderNormalizedRect(
              left: frameLeft / screenW,
              top: frameTop / screenH,
              width: frameW / screenW,
              height: frameH / screenH,
            ));
          });
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Semi-transparent dark mask with clear cutout for card interior
            CustomPaint(
              size: Size(screenW, screenH),
              painter: _CardViewfinderMaskPainter(
                cutoutRect: frameRect,
                cornerRadius: 16.0,
                scrimColor: Colors.black.withValues(alpha: 0.65),
              ),
            ),

            // 2. Corner Guides & Border (unobstructed transparent interior for camera preview)
            Positioned(
              left: frameRect.left,
              top: frameRect.top,
              width: frameRect.width,
              height: frameRect.height,
              child: CustomPaint(
                painter: _CornerGuidePainter(
                  color: isReady
                      ? const Color(0xFF10B981) // Green when ready
                      : theme.colorScheme.primary,
                  cornerLength: 26.0,
                  strokeWidth: 3.5,
                  borderRadius: 16.0,
                ),
              ),
            ),

            // 2b. Visible Outline Around Detected Business Card (Document Scanner Quad & Corner Pins)
            if (detectedPolygon != null && detectedPolygon!.length == 4)
              IgnorePointer(
                child: CustomPaint(
                  size: Size(screenW, screenH),
                  painter: _DocumentScannerBoundaryPainter(
                    polygon: detectedPolygon!,
                    autoCaptureProgress: autoCaptureProgress,
                    detectionState: detectionState,
                  ),
                ),
              )
            else if (detectedCardRect != null)
              Positioned.fromRect(
                rect: detectedCardRect!,
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: const Color(0xFF10B981),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.40),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 10, color: Colors.white),
                              SizedBox(width: 3),
                              Text(
                                'Card Detected',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 3. Top Header Bar (Title, Side Badge, Torch, Cancel)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      // Cancel Button
                      IconButton(
                        key: const Key('camera_cancel_button'),
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 26),
                        tooltip: 'Cancel',
                        onPressed: onCancel,
                      ),
                      const SizedBox(width: 8),

                      // Title & Side indicator
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Scan Business Card',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary
                                    .withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$sideName SIDE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Camera Lens Switcher Button (where supported)
                      if (onSwitchCamera != null)
                        IconButton(
                          key: const Key('camera_switch_lens_button'),
                          icon: const Icon(
                            Icons.cameraswitch_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          tooltip: 'Switch Camera Lens',
                          onPressed: onSwitchCamera,
                        ),

                      // Torch Toggle Button
                      IconButton(
                        key: const Key('camera_torch_button'),
                        icon: Icon(
                          isTorchOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          color: isTorchOn ? Colors.amber : Colors.white,
                          size: 24,
                        ),
                        tooltip: isTorchOn ? 'Turn Flash Off' : 'Turn Flash On',
                        onPressed: onToggleTorch,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 4. Guidance State Indicator (Pill above frame)
            Positioned(
              left: 24,
              right: 24,
              top: max(72.0, frameRect.top - 52),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getGuidanceBgColor(theme, guidanceMessage),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getGuidanceIcon(guidanceMessage),
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          guidanceMessage,
                          key: const Key('camera_guidance_text'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 5. Bottom Controls (Shutter Button, Gallery Shortcut, Side Switch)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Auto-Capture Mode Indicator & Toggle
                      if (onToggleAutoCapture != null) ...[
                        FilterChip(
                          key: const Key('toggle_auto_capture_button'),
                          avatar: Icon(
                            isAutoCapture
                                ? Icons.auto_awesome_rounded
                                : Icons.touch_app_rounded,
                            size: 14,
                            color: isAutoCapture
                                ? const Color(0xFF10B981)
                                : Colors.white70,
                          ),
                          label: Text(
                            isAutoCapture
                                ? 'Auto Capture: Active'
                                : 'Manual Shutter',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isAutoCapture
                                  ? const Color(0xFF10B981)
                                  : Colors.white,
                            ),
                          ),
                          selected: isAutoCapture,
                          onSelected: (_) => onToggleAutoCapture?.call(),
                          backgroundColor: Colors.black54,
                          selectedColor:
                              const Color(0xFF10B981).withValues(alpha: 0.25),
                          side: BorderSide(
                            color: isAutoCapture
                                ? const Color(0xFF10B981)
                                : Colors.white30,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Switch Side Button (Front/Back)
                          if (onToggleSide != null)
                            IconButton(
                              key: const Key('camera_side_switch_button'),
                              icon: const Icon(Icons.flip_rounded,
                                  color: Colors.white, size: 28),
                              tooltip: 'Switch Card Side',
                              onPressed: onToggleSide,
                            )
                          else
                            const SizedBox(width: 48),

                          // Main Shutter Button with Auto-Capture Countdown Indicator
                          GestureDetector(
                            key: const Key('camera_capture_shutter_button'),
                            onTap: isCaptureEnabled ? onCapture : null,
                            child: Opacity(
                              opacity: isCaptureEnabled ? 1.0 : 0.45,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  if (autoCaptureProgress > 0.0)
                                    SizedBox(
                                      width: 86,
                                      height: 86,
                                      child: CircularProgressIndicator(
                                        value: autoCaptureProgress,
                                        strokeWidth: 4.5,
                                        valueColor: const AlwaysStoppedAnimation<Color>(
                                          Color(0xFF10B981),
                                        ),
                                        backgroundColor: Colors.white24,
                                      ),
                                    ),
                                  Container(
                                    width: 76,
                                    height: 76,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 4,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(4),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Gallery Shortcut Button
                          IconButton(
                            key: const Key('camera_gallery_button'),
                            icon: const Icon(Icons.photo_library_rounded,
                                color: Colors.white, size: 28),
                            tooltip: 'Choose from Gallery',
                            onPressed: onPickGallery,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Capture',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Shutter capture flash animation
            if (isFlashing)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Color _getGuidanceBgColor(ThemeData theme, String message) {
    final lower = message.toLowerCase();
    if (lower.contains('ready')) {
      return const Color(0xFF10B981); // Emerald green
    }
    if (lower.contains('too dark') || lower.contains('glare')) {
      return const Color(0xFFD97706); // Amber
    }
    if (lower.contains('steady') || lower.contains('visible')) {
      return const Color(0xFF3B82F6); // Blue
    }
    return Colors.black.withValues(alpha: 0.65);
  }

  IconData _getGuidanceIcon(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('ready')) return Icons.check_circle_outline_rounded;
    if (lower.contains('too dark')) return Icons.wb_incandescent_outlined;
    if (lower.contains('glare')) return Icons.flare_rounded;
    if (lower.contains('steady')) return Icons.screen_lock_rotation_rounded;
    if (lower.contains('closer')) return Icons.zoom_in_rounded;
    if (lower.contains('farther')) return Icons.zoom_out_rounded;
    if (lower.contains('entire') || lower.contains('visible')) {
      return Icons.crop_free_rounded;
    }
    return Icons.filter_center_focus_rounded;
  }
}

/// Custom painter that carves out a rounded rectangular clear window in a semi-transparent scrim.
class _CardViewfinderMaskPainter extends CustomPainter {
  final Rect cutoutRect;
  final double cornerRadius;
  final Color scrimColor;

  const _CardViewfinderMaskPainter({
    required this.cutoutRect,
    required this.cornerRadius,
    required this.scrimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        cutoutRect,
        Radius.circular(cornerRadius),
      ));

    // Combine via difference to create hollow frame
    final maskPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final paint = Paint()
      ..color = scrimColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(maskPath, paint);
  }

  @override
  bool shouldRepaint(covariant _CardViewfinderMaskPainter oldDelegate) {
    return oldDelegate.cutoutRect != cutoutRect ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.cornerRadius != cornerRadius;
  }
}

/// Draws rounded corner indicators at the 4 extremities of the business card frame.
class _CornerGuidePainter extends CustomPainter {
  final Color color;
  final double cornerLength;
  final double strokeWidth;
  final double borderRadius;

  const _CornerGuidePainter({
    required this.color,
    required this.cornerLength,
    required this.strokeWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final r = borderRadius;
    final len = cornerLength;

    // Top-Left
    final tlPath = Path()
      ..moveTo(0, r + len)
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..lineTo(r + len, 0);
    canvas.drawPath(tlPath, paint);

    // Top-Right
    final trPath = Path()
      ..moveTo(w - r - len, 0)
      ..lineTo(w - r, 0)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..lineTo(w, r + len);
    canvas.drawPath(trPath, paint);

    // Bottom-Left
    final blPath = Path()
      ..moveTo(0, h - r - len)
      ..lineTo(0, h - r)
      ..arcToPoint(Offset(r, h), radius: Radius.circular(r))
      ..lineTo(r + len, h);
    canvas.drawPath(blPath, paint);

    // Bottom-Right
    final brPath = Path()
      ..moveTo(w - r - len, h)
      ..lineTo(w - r, h)
      ..arcToPoint(Offset(w, h - r), radius: Radius.circular(r))
      ..lineTo(w, h - r - len);
    canvas.drawPath(brPath, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerGuidePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerLength != cornerLength ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Professional document-scanner boundary painter (Adobe Scan / MS Lens style).
/// Renders glowing boundary edges, translucent polygon interior, 4 corner pins, and anchored status badge.
class _DocumentScannerBoundaryPainter extends CustomPainter {
  final List<Offset> polygon;
  final double autoCaptureProgress;
  final CardDetectionState detectionState;

  const _DocumentScannerBoundaryPainter({
    required this.polygon,
    this.autoCaptureProgress = 0.0,
    this.detectionState = CardDetectionState.searching,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (polygon.length < 4) return;

    final path = Path()
      ..moveTo(polygon[0].dx, polygon[0].dy)
      ..lineTo(polygon[1].dx, polygon[1].dy)
      ..lineTo(polygon[2].dx, polygon[2].dy)
      ..lineTo(polygon[3].dx, polygon[3].dy)
      ..close();

    final bool isStable = detectionState == CardDetectionState.stabilizing ||
        detectionState == CardDetectionState.capturing ||
        detectionState == CardDetectionState.processing;
    final primaryColor = isStable ? const Color(0xFF10B981) : const Color(0xFF38BDF8);
    final coreColor = isStable ? const Color(0xFF047857) : const Color(0xFF0369A1);

    // 1. Translucent quad fill
    final fillPaint = Paint()
      ..color = primaryColor.withValues(alpha: isStable ? 0.20 : 0.12)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    // 2. Outer soft glow border
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isStable ? 0.45 : 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);

    // 3. Inner crisp edge border
    final strokePaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, strokePaint);

    // 4. Four prominent corner pins with adaptive progress glow
    final glowRadius = 8.0 + (autoCaptureProgress * 3.5);
    for (int i = 0; i < 4; i++) {
      final pt = polygon[i];

      // Outer glow circle
      canvas.drawCircle(
        pt,
        glowRadius,
        Paint()..color = primaryColor.withValues(alpha: 0.45),
      );
      // Outer ring
      canvas.drawCircle(
        pt,
        6.0,
        Paint()
          ..color = primaryColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
      // Inner white node
      canvas.drawCircle(
        pt,
        4.0,
        Paint()..color = Colors.white,
      );
      // Center core
      canvas.drawCircle(
        pt,
        1.8,
        Paint()..color = coreColor,
      );
    }

    // 5. Anchored Status Badge above top edge midpoint
    final midTopX = (polygon[0].dx + polygon[1].dx) / 2.0;
    final midTopY = (polygon[0].dy + polygon[1].dy) / 2.0 - 24.0;

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(midTopX, max(20.0, midTopY)),
        width: isStable ? 124.0 : 100.0,
        height: 22.0,
      ),
      const Radius.circular(11.0),
    );

    // Badge shadow & background
    canvas.drawRRect(
      badgeRect,
      Paint()
        ..color = coreColor
        ..style = PaintingStyle.fill,
    );

    String badgeLabel;
    if (detectionState == CardDetectionState.stabilizing) {
      badgeLabel = 'Hold Steady ${(autoCaptureProgress * 100).toInt()}%';
    } else if (detectionState == CardDetectionState.capturing ||
        detectionState == CardDetectionState.processing) {
      badgeLabel = 'Capturing Card';
    } else {
      badgeLabel = autoCaptureProgress > 0.0
          ? 'Card Detected ${(autoCaptureProgress * 100).toInt()}%'
          : 'Card Detected';
    }

    // Text & countdown indicator
    final textSpan = TextSpan(
      text: badgeLabel,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(
        midTopX - (textPainter.width / 2.0),
        max(20.0, midTopY) - (textPainter.height / 2.0),
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _DocumentScannerBoundaryPainter oldDelegate) {
    if (oldDelegate.detectionState != detectionState) return true;
    if (oldDelegate.autoCaptureProgress != autoCaptureProgress) return true;
    if (oldDelegate.polygon.length != polygon.length) return true;
    for (int i = 0; i < polygon.length; i++) {
      if (oldDelegate.polygon[i] != polygon[i]) return true;
    }
    return false;
  }
}
