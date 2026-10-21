import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import 'auth/login_screen.dart';
import 'home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  final AuthService? authService;
  final ProfileService? profileService;
  final Duration initialDelay;

  const SplashScreen({
    super.key,
    this.authService,
    this.profileService,
    this.initialDelay = const Duration(milliseconds: 600),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late final AuthService _authService;
  late final ProfileService _profileService;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _profileService = widget.profileService ?? ProfileService();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    // Add small delay for smooth visual transition
    if (widget.initialDelay > Duration.zero) {
      await Future.delayed(widget.initialDelay);
    }

    if (!mounted) return;

    if (kDebugMode) {
      debugPrint('[Auth] restore started');
    }

    bool hasToken = false;
    try {
      hasToken = await _authService.hasStoredToken();
      if (kDebugMode) {
        debugPrint('[Auth] stored token exists=$hasToken');
      }
      if (!hasToken) {
        _navigateToLogin();
        return;
      }

      // Validate session against the backend
      final profile = await _profileService.getMyProfile();
      if (kDebugMode) {
        debugPrint('[Auth] validation=valid');
      }
      if (!mounted) return;
      _navigateToHome(profile);
    } on UnauthorizedException {
      if (kDebugMode) {
        debugPrint('[Auth] validation=unauthorized');
      }
      await _authService.logout();
      if (!mounted) return;
      _navigateToLogin();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[Auth] validation=network-error');
      }
      // CRITICAL RELIABILITY: A temporary network error, socket exception,
      // timeout, or 5xx server failure MUST NOT delete the token or kick the user out.
      // We navigate to Home preserving local auth session.
      if (!mounted) return;
      _navigateToHome(null);
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _navigateToHome(dynamic profile) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => HomeScreen(initialProfile: profile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.badge_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Digital Share',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Digital Identity & Contact Card',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
