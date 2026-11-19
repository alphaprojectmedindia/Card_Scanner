import 'package:flutter/material.dart';
import '../../models/country_calling_code.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/legal_consent_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/digital_share_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../../widgets/primary_button.dart';
import '../home/home_screen.dart';
import '../legal/mandatory_consent_dialog.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  CountryCallingCode _selectedCountry = CountryCallingCode.defaultCountry; // Default India +91
  bool _useEmailLogin = false;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      if (_useEmailLogin) {
        await _authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        final digitsOnly =
            _phoneController.text.trim().replaceAll(RegExp(r'[^\d]'), '');
        final fullPhone = '${_selectedCountry.code}$digitsOnly';

        await _authService.login(
          phoneNumber: fullPhone,
          password: _passwordController.text,
        );
      }

      if (!mounted) return;

      // Check whether user has accepted the current mandatory terms
      final consentStatus = await LegalConsentService().checkConsentStatus();
      if (!consentStatus.hasAcceptedCurrentTerms) {
        if (!mounted) return;
        final accepted = await MandatoryConsentDialog.show(
          context,
          initialJurisdiction: consentStatus.jurisdiction,
        );
        if (accepted != true) {
          return;
        }
      }

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
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
                  Center(
                    child: const DigitalShareLogo(
                      height: 84,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to access your digital contact card',
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
                  if (!_useEmailLogin) ...[
                    // Mobile Number with Country Calling Code Selector
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mobile Number *',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 52,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<CountryCallingCode>(
                                  key: const Key('login_country_code_dropdown'),
                                  value: _selectedCountry,
                                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                                  items: CountryCallingCode.supported.map((country) {
                                    return DropdownMenuItem<CountryCallingCode>(
                                      value: country,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(country.flag,
                                              style: const TextStyle(fontSize: 18)),
                                          const SizedBox(width: 6),
                                          Text(
                                            country.code,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newCountry) {
                                    if (newCountry != null) {
                                      setState(() {
                                        _selectedCountry = newCountry;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                key: const Key('login_phone_field'),
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                decoration: InputDecoration(
                                  hintText: _selectedCountry.code == '+91'
                                      ? '98765 43210'
                                      : 'Phone number',
                                  hintStyle: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                  prefixIcon:
                                      const Icon(Icons.phone_outlined, size: 20),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.35),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your mobile number.';
                                  }
                                  final digitsOnly =
                                      value.replaceAll(RegExp(r'[^\d]'), '');
                                  if (digitsOnly.length < 7 ||
                                      digitsOnly.length > 15) {
                                    return 'Please enter a valid mobile number (7-15 digits).';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    CustomTextField(
                      controller: _emailController,
                      label: 'Email Address',
                      hint: 'name@example.com',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your email address.';
                        }
                        if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                            .hasMatch(value.trim())) {
                          return 'Please enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      key: const Key('toggle_login_method_button'),
                      onPressed: () {
                        setState(() {
                          _useEmailLogin = !_useEmailLogin;
                          _errorMessage = '';
                        });
                      },
                      child: Text(
                        _useEmailLogin
                            ? 'Use Mobile Number instead'
                            : 'Use Email Address instead',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Enter your password',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  PrimaryButton(
                    text: 'Sign In',
                    isLoading: _isLoading,
                    icon: Icons.login_rounded,
                    onPressed: _handleLogin,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Register',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
