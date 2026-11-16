import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/imported_contact_service.dart';
import '../../services/secure_storage_service.dart';
import '../../theme/app_spacing.dart';
import '../auth/login_screen.dart';

class DeleteAccountScreen extends StatefulWidget {
  final AuthService? authService;
  final ImportedContactService? contactService;
  final ApiClient? apiClient;
  final SecureStorageService? storageService;
  final int? initialCardCount;
  final int? initialConnectionCount;
  final int? initialMeetingCount;

  const DeleteAccountScreen({
    super.key,
    this.authService,
    this.contactService,
    this.apiClient,
    this.storageService,
    this.initialCardCount,
    this.initialConnectionCount,
    this.initialMeetingCount,
  });

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late final AuthService _authService;
  late final ImportedContactService _contactService;
  late final ApiClient _apiClient;
  late final SecureStorageService _storageService;

  int _currentStep = 0;
  bool _isLoadingSummary = true;
  bool _isDeleting = false;
  String? _errorMessage;

  // Summary counts
  int _cardCount = 0;
  int _connectionCount = 0;
  int _meetingCount = 0;

  // Step 3 & 4 controllers
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmationTextController = TextEditingController();
  bool _obscurePassword = true;
  bool _confirmedCheckbox = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _contactService = widget.contactService ?? ImportedContactService();
    _apiClient = widget.apiClient ?? ApiClient();
    _storageService = widget.storageService ?? SecureStorageService();

    if (widget.initialCardCount != null ||
        widget.initialConnectionCount != null ||
        widget.initialMeetingCount != null) {
      _cardCount = widget.initialCardCount ?? 0;
      _connectionCount = widget.initialConnectionCount ?? 0;
      _meetingCount = widget.initialMeetingCount ?? 0;
      _isLoadingSummary = false;
    } else {
      _loadDataSummary();
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationTextController.dispose();
    super.dispose();
  }

  Future<void> _loadDataSummary() async {
    try {
      final cards = await _contactService.getContacts();
      _cardCount = cards.length;
    } catch (_) {}

    try {
      final connRes = await _apiClient.get(ApiConfig.connectionsEndpoint, requiresAuth: true);
      if (connRes is List) {
        _connectionCount = connRes.length;
      }
    } catch (_) {}

    try {
      final meetRes = await _apiClient.get(ApiConfig.meetingsEndpoint, requiresAuth: true);
      if (meetRes is List) {
        _meetingCount = meetRes.length;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoadingSummary = false;
      });
    }
  }

  void _nextStep() {
    setState(() {
      _errorMessage = null;
    });

    if (_currentStep == 2) {
      // Validate password not empty before advancing to step 4
      if (_passwordController.text.trim().isEmpty) {
        setState(() {
          _errorMessage = 'Password is required to proceed.';
        });
        return;
      }
    }

    if (_currentStep < 3) {
      setState(() {
        _currentStep++;
      });
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleDeleteAccount() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'Password is required.';
      });
      return;
    }

    if (!_confirmedCheckbox) {
      setState(() {
        _errorMessage = 'You must confirm that you understand this action is permanent.';
      });
      return;
    }

    if (_confirmationTextController.text.trim().toUpperCase() != 'DELETE') {
      setState(() {
        _errorMessage = "Please type 'DELETE' in the confirmation field to confirm.";
      });
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      // 1. Delete on backend and clear auth
      await _authService.deleteAccount(password: password);

      // 2. Clear local disk repository
      try {
        await _contactService.localRepository.clearAllLocalContacts();
      } catch (_) {}

      // 3. Clear all cached storage
      try {
        await _storageService.clearAuth();
      } catch (_) {}

      if (!mounted) return;

      // 4. Show success snackbar and route to login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account and all associated data have been permanently deleted.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = e.message.isNotEmpty
              ? e.message
              : 'Incorrect password or account deletion failed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _errorMessage = 'Failed to delete account: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delete Account'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step Progress Indicator
            LinearProgressIndicator(
              value: (_currentStep + 1) / 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: theme.colorScheme.error,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Step ${_currentStep + 1} of 4',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  Text(
                    _getStepTitle(_currentStep),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Step Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: theme.colorScheme.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildStepContent(theme),
                  ],
                ),
              ),
            ),

            // Navigation Controls
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    offset: const Offset(0, -2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    OutlinedButton(
                      key: const Key('delete_account_back_button'),
                      onPressed: _isDeleting ? null : _previousStep,
                      child: const Text('Back'),
                    )
                  else
                    TextButton(
                      key: const Key('delete_account_cancel_button'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  const Spacer(),
                  if (_currentStep < 3)
                    FilledButton(
                      key: const Key('delete_account_next_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _currentStep == 0 ? theme.colorScheme.error : null,
                      ),
                      onPressed: _nextStep,
                      child: const Text('Continue'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('delete_account_confirm_button'),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                      ),
                      icon: _isDeleting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onError,
                              ),
                            )
                          : const Icon(Icons.delete_forever_rounded),
                      label: Text(_isDeleting ? 'Deleting...' : 'Permanently Delete My Account'),
                      onPressed: _isDeleting ? null : _handleDeleteAccount,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStepTitle(int step) {
    switch (step) {
      case 0:
        return 'Warning';
      case 1:
        return 'Data Summary';
      case 2:
        return 'Password Reauthentication';
      case 3:
        return 'Final Confirmation';
      default:
        return '';
    }
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Warning(theme);
      case 1:
        return _buildStep2DataSummary(theme);
      case 2:
        return _buildStep3Password(theme);
      case 3:
        return _buildStep4FinalConfirmation(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep1Warning(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.warning_amber_rounded,
              size: 48,
              color: theme.colorScheme.error,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Delete Your Account Permanently',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'This action is permanent and completely irreversible. Once your account is deleted, your data cannot be recovered under any circumstances.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'What will be deleted:',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildBulletItem(theme, Icons.person_remove_outlined, 'Your profile details and digital business card.'),
        _buildBulletItem(theme, Icons.contact_phone_outlined, 'All imported cards, contacts, and personal remarks.'),
        _buildBulletItem(theme, Icons.people_outline, 'All connections and contact interactions.'),
        _buildBulletItem(theme, Icons.calendar_today_outlined, 'All scheduled meetings and availability settings.'),
        _buildBulletItem(theme, Icons.image_not_supported_outlined, 'All uploaded card images and profile photos.'),
      ],
    );
  }

  Widget _buildStep2DataSummary(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Data Impact Summary',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Here is a summary of the data currently stored in your Digital Share account:',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        if (_isLoadingSummary)
          const Center(child: CircularProgressIndicator())
        else ...[
          _buildSummaryCard(
            theme,
            icon: Icons.contact_phone_rounded,
            count: _cardCount,
            title: 'Imported Business Cards',
            subtitle: '$_cardCount imported cards and personal notes will be deleted.',
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            theme,
            icon: Icons.people_alt_rounded,
            count: _connectionCount,
            title: 'Saved Connections',
            subtitle: '$_connectionCount user connections will be removed.',
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            theme,
            icon: Icons.calendar_month_rounded,
            count: _meetingCount,
            title: 'Meetings & Schedule',
            subtitle: '$_meetingCount scheduled meetings will be cancelled.',
          ),
        ],
      ],
    );
  }

  Widget _buildStep3Password(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm Your Password',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'For your security, please enter your password to verify your identity before proceeding.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('delete_account_password_field'),
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Account Password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4FinalConfirmation(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.error),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.report_problem_rounded, color: theme.colorScheme.error, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Final Warning',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is the point of no return. Once you confirm, your account will be deleted immediately and your session will be terminated.',
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        CheckboxListTile(
          key: const Key('delete_account_understand_checkbox'),
          value: _confirmedCheckbox,
          onChanged: (val) {
            setState(() {
              _confirmedCheckbox = val ?? false;
            });
          },
          title: const Text(
            'I understand this action cannot be undone.',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: 16),
        Text(
          'Type "DELETE" below to authorize permanent account removal:',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('delete_account_confirm_text_field'),
          controller: _confirmationTextController,
          decoration: InputDecoration(
            hintText: 'DELETE',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletItem(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme, {
    required IconData icon,
    required int count,
    required String title,
    required String subtitle,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
