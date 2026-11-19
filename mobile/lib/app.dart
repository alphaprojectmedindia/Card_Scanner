import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class DigitalShareApp extends StatelessWidget {
  final ThemeController? themeController;

  const DigitalShareApp({super.key, this.themeController});

  @override
  Widget build(BuildContext context) {
    final controller = themeController ?? ThemeController.instance;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final platformBrightness =
            MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.light;
        final isDark = controller.themeMode == ThemeMode.dark ||
            (controller.themeMode == ThemeMode.system &&
                platformBrightness == Brightness.dark);
        final overlayStyle =
            isDark ? AppTheme.darkOverlayStyle : AppTheme.lightOverlayStyle;

        // Apply immediately to native system UI
        SystemChrome.setSystemUIOverlayStyle(overlayStyle);

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: MaterialApp(
            title: 'Digital Share',
            debugShowCheckedModeBanner: false,
            themeMode: controller.themeMode,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            home: const SplashScreen(),
          ),
        );
      },
    );
  }
}
