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
import '../legal/legal_documents_screen.dart';
import '../../config/legal_urls.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final AuthService _authService = AuthService();

  CountryCallingCode _selectedCountry = CountryCallingCode.defaultCountry; // Default India +91
  bool _isLoading = false;
  String _errorMessage = '';
  bool _termsAccepted = false; // Unchecked mandatory consent
  bool _analyticsAccepted = false;
  late String _jurisdiction;

  @override
  void initState() {
    super.initState();
    _jurisdiction = LegalConsentService().resolveJurisdiction(
      explicitCallingCode: _selectedCountry.code,
      explicitCountryCode: _selectedCountry.isoCode,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _openTerms() async {
    final launched = await LegalUrls.openTermsAndConditions();
    if (!launched && mounted) {
      _openLegalDocuments(0);
    }
  }

  Future<void> _openPrivacy() async {
    final launched = await LegalUrls.openPrivacyPolicy();
    if (!launched && mounted) {
      _openLegalDocuments(1);
    }
  }

  void _openLegalDocuments(int tabIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentsScreen(
          initialJurisdiction: _jurisdiction,
          initialTab: tabIndex,
        ),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (!_termsAccepted) {
      setState(() {
        _errorMessage =
            'Accepting the Terms and Conditions and Privacy Policy is required.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final digitsOnly =
          _phoneController.text.trim().replaceAll(RegExp(r'[^\d]'), '');
      final fullPhoneNumber = '${_selectedCountry.code}$digitsOnly';

      await _authService.register(
        email: _emailController.text,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
        phoneNumber: fullPhoneNumber,
        termsAccepted: _termsAccepted,
        jurisdiction: _jurisdiction,
        analyticsAccepted: _analyticsAccepted,
      );

      await LegalConsentService().recordConsent(
        jurisdiction: _jurisdiction,
        essentialAccepted: true,
        analyticsAccepted: _analyticsAccepted,
      );

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
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
        title: const Text('Create Account'),
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
                  Center(
                    child: const DigitalShareLogo(
                      height: 72,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Get Started with Digital Share',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your account to start sharing your digital card',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_errorMessage.isNotEmpty)
                    ErrorBanner(
                      message: _errorMessage,
                      onDismiss: () => setState(() => _errorMessage = ''),
                    ),
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
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                        return 'Please enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    controller: _passwordController,
                    label: 'Password',
                    hint: 'Minimum 6 characters',
                    prefixIcon: Icons.lock_outline,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password.';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters long.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  CustomTextField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    hint: 'Re-enter your password',
                    prefixIcon: Icons.lock_reset_outlined,
                    isPassword: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password.';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

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
                                key: const Key('register_country_code_dropdown'),
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
                                      _jurisdiction = LegalConsentService()
                                          .resolveJurisdiction(
                                        explicitCallingCode: newCountry.code,
                                        explicitCountryCode: newCountry.isoCode,
                                      );
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              key: const Key('register_phone_field'),
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
                                prefixIcon: const Icon(Icons.phone_outlined, size: 20),
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
                                if (digitsOnly.length < 7 || digitsOnly.length > 15) {
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
                  const SizedBox(height: 20),

                  // Simplified & Clean Legal Consent Section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerLow
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              key: const Key('register_terms_checkbox'),
                              value: _termsAccepted,
                              onChanged: (val) {
                                setState(() {
                                  _termsAccepted = val ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    const Text(
                                      'I agree to the ',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    GestureDetector(
                                      onTap: _openTerms,
                                      child: Text(
                                        'Terms and Conditions',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      ' and ',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    GestureDetector(
                                      onTap: _openPrivacy,
                                      child: Text(
                                        'Privacy Policy',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    const Text('.', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 48.0, bottom: 4.0),
                          child: GestureDetector(
                            onTap: () => _openLegalDocuments(2),
                            child: Text(
                              'Cookie Policy',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Optional Analytics Checkbox
                  CheckboxListTile(
                    key: const Key('register_analytics_checkbox'),
                    value: _analyticsAccepted,
                    onChanged: (val) {
                      setState(() {
                        _analyticsAccepted = val ?? false;
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'Allow optional anonymous usage analytics to help improve Digital Share.',
                      style: TextStyle(fontSize: 12),
                    ),
                    subtitle: const Text(
                      'Declining analytics will not affect any application functionality.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 20),

                  PrimaryButton(
                    key: const Key('register_submit_button'),
                    text: 'Register Account',
                    isLoading: _isLoading,
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: _termsAccepted ? _handleRegister : null,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          'Sign In',
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
