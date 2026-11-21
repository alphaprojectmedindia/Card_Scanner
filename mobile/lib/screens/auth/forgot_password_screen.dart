import 'package:flutter/material.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/digital_share_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../../widgets/primary_button.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final AuthService? authService;

  const ForgotPasswordScreen({super.key, this.authService});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late final AuthService _authService;

  bool _isLoading = false;
  String _errorMessage = '';
  String _successMessage = '';

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleForgotPassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      final message = await _authService.forgotPassword(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _successMessage = message;
      });
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
        title: const Text('Reset Password'),
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
                    'Forgot Password?',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your registered email address and we will send you a password reset link and token.',
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
                  if (_successMessage.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 22),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Email Sent',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _successMessage,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const Key('enter_reset_token_button'),
                              icon: const Icon(Icons.key_rounded, size: 18),
                              label: const Text('Enter Reset Token & Set Password'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.primary,
                                side: BorderSide(color: theme.colorScheme.primary),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ResetPasswordScreen(
                                      initialEmail: _emailController.text.trim(),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  CustomTextField(
                    key: const Key('forgot_email_field'),
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
                  const SizedBox(height: 24),
                  PrimaryButton(
                    key: const Key('send_reset_link_button'),
                    text: 'Send Reset Link',
                    isLoading: _isLoading,
                    icon: Icons.send_rounded,
                    onPressed: _handleForgotPassword,
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ResetPasswordScreen(
                            initialEmail: _emailController.text.trim(),
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Already have a reset token? Click here',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.primary,
                      ),
                    ),
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
