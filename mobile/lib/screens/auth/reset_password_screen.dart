import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/digital_share_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../../widgets/primary_button.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? initialEmail;
  final String? initialToken;
  final AuthService? authService;

  const ResetPasswordScreen({
    super.key,
    this.initialEmail,
    this.initialToken,
    this.authService,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _tokenController;
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  late final AuthService _authService;

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _tokenController = TextEditingController(text: widget.initialToken ?? '');
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _tokenController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _authService.resetPassword(
        email: _emailController.text.trim(),
        token: _tokenController.text.trim(),
        newPassword: _newPasswordController.text,
        confirmPassword: _confirmPasswordController.text,
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 48),
          title: const Text('Password Reset Successful'),
          content: const Text(
            'Your password has been changed successfully. Please log in with your new password.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('Go to Login'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set New Password'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: DigitalShareLogo(height: 72),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Create New Password',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the reset token sent to your email along with your new password.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage.isNotEmpty)
                    ErrorBanner(
                      message: _errorMessage,
                      onDismiss: () => setState(() => _errorMessage = ''),
                    ),
                  CustomTextField(
                    key: const Key('reset_email_field'),
                    controller: _emailController,
                    label: 'Email Address *',
                    hint: 'name@example.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email address.';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                        return 'Please enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    key: const Key('reset_token_field'),
                    controller: _tokenController,
                    label: 'Reset Token *',
                    hint: 'Paste the reset token from your email',
                    prefixIcon: Icons.vpn_key_outlined,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter the reset token.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    key: const Key('reset_new_password_field'),
                    controller: _newPasswordController,
                    label: 'New Password *',
                    hint: 'Enter new password (min. 6 characters)',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your new password.';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomTextField(
                    key: const Key('reset_confirm_password_field'),
                    controller: _confirmPasswordController,
                    label: 'Confirm New Password *',
                    hint: 'Confirm your new password',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your new password.';
                      }
                      if (value != _newPasswordController.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    key: const Key('confirm_reset_password_button'),
                    text: 'Reset Password',
                    isLoading: _isLoading,
                    icon: Icons.check_circle_outline,
                    onPressed: _handleResetPassword,
                  ),
                  const SizedBox(height: 24),
                  const MedindiaBrandingFooter(showDivider: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
