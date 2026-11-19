import 'package:flutter/material.dart';

/// Centralized Medindia4u.com footer branding widget.
///
/// Displays the official "Powered by Medindia4u.com" branding text
/// with clean typography, responsive layout, and theme-adaptive colors.
class MedindiaBrandingFooter extends StatelessWidget {
  /// Whether to display a subtle top divider line above the branding text.
  final bool showDivider;

  /// Custom padding around the footer.
  final EdgeInsetsGeometry padding;

  /// Optional custom font size.
  final double? fontSize;

  const MedindiaBrandingFooter({
    super.key,
    this.showDivider = false,
    this.padding = const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: padding,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showDivider) ...[
                Divider(
                  height: 1,
                  thickness: 0.8,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Powered by Medindia4u.com',
                key: const Key('medindia_branding_footer_text'),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: fontSize ?? 12,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

