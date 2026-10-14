import 'package:flutter/material.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_controller.dart';

/// Dialog allowing user to switch between System Default, Light, and Dark themes.
class ThemeSelectionDialog extends StatelessWidget {
  final ThemeController themeController;

  ThemeSelectionDialog({
    super.key,
    ThemeController? controller,
  }) : themeController = controller ?? ThemeController.instance;

  static Future<void> show(BuildContext context, {ThemeController? controller}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ThemeSelectionDialog(controller: controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentMode = themeController.themeMode;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.palette_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          const Text('Appearance'),
        ],
      ),
      contentPadding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
      content: RadioGroup<ThemeMode>(
        groupValue: currentMode,
        onChanged: (mode) {
          if (mode != null) {
            themeController.setThemeMode(mode);
            Navigator.of(context).pop();
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<ThemeMode>(
              value: ThemeMode.system,
              secondary: const Icon(Icons.phone_android_rounded),
              title: const Text('System Default'),
              subtitle: const Text('Match device light/dark appearance'),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.light,
              secondary: const Icon(Icons.light_mode_rounded),
              title: const Text('Light'),
              subtitle: const Text('Clean white & slate surfaces'),
            ),
            RadioListTile<ThemeMode>(
              value: ThemeMode.dark,
              secondary: const Icon(Icons.dark_mode_rounded),
              title: const Text('Dark'),
              subtitle: const Text('Deep slate surfaces easy on the eyes'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
