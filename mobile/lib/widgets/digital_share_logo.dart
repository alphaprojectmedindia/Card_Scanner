import 'package:flutter/material.dart';

/// The official Digital Share brand logo widget.
///
/// Renders the official 3D profile sharing network asset with
/// high fidelity and preserved aspect ratio.
class DigitalShareLogo extends StatelessWidget {
  /// Optional width of the logo.
  final double? width;

  /// Optional height of the logo.
  final double? height;

  /// Convenience parameter to set both width and height to the same dimension.
  final double? size;

  /// How the image should be inscribed into the box.
  final BoxFit fit;

  /// Alignment within the container.
  final AlignmentGeometry alignment;

  /// Optional semantic label for accessibility.
  final String? semanticLabel;

  const DigitalShareLogo({
    super.key,
    this.width,
    this.height,
    this.size,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.semanticLabel = 'Digital Share Logo',
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = size ?? width;
    final effectiveHeight = size ?? height;

    return Image.asset(
      'assets/images/digital_share_logo.png',
      width: effectiveWidth,
      height: effectiveHeight,
      fit: fit,
      alignment: alignment,
      semanticLabel: semanticLabel,
    );
  }
}
