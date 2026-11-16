import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../theme/app_spacing.dart';

class AccountVisibilityScreen extends StatefulWidget {
  final ProfileService? profileService;
  final bool? initialIsPublic;

  const AccountVisibilityScreen({
    super.key,
    this.profileService,
    this.initialIsPublic,
  });

  @override
  State<AccountVisibilityScreen> createState() => _AccountVisibilityScreenState();
}

class _AccountVisibilityScreenState extends State<AccountVisibilityScreen> {
  late final ProfileService _profileService;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isPublic = false;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? ProfileService();
    if (widget.initialIsPublic != null) {
      _isPublic = widget.initialIsPublic!;
      _isLoading = false;
    } else {
      _loadVisibility();
    }
  }

  Future<void> _loadVisibility() async {
    try {
      final isPub = await _profileService.getVisibility();
      if (mounted) {
        setState(() {
          _isPublic = isPub;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setVisibility(bool newValue) async {
    if (_isSaving || newValue == _isPublic) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final updated = await _profileService.updateVisibility(newValue);
      if (mounted) {
        setState(() {
          _isPublic = updated;
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isPublic
                  ? 'Account is now Public and discoverable.'
                  : 'Account is now Private and hidden from search.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update visibility: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Visibility'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                // Info Banner
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusMd,
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.privacy_tip_outlined,
                          color: theme.colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Privacy & Discovery',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Control whether your business profile can be found by others in Digital Share searches. Your personal remarks and scanned cards are always strictly private.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Option 1: Private Account (Default)
                InkWell(
                  key: const Key('visibility_private_option'),
                  onTap: _isSaving ? null : () => _setVisibility(false),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: !_isPublic
                          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: !_isPublic
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: !_isPublic ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: !_isPublic
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: !_isPublic
                              ? Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Private Account',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Default',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your profile is completely hidden from public searches and discovery.\n\nOnly people with whom you explicitly share your QR code or direct link can view your digital business card.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Option 2: Public Account
                InkWell(
                  key: const Key('visibility_public_option'),
                  onTap: _isSaving ? null : () => _setVisibility(true),
                  borderRadius: BorderRadius.circular(16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isPublic
                          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isPublic
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: _isPublic ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isPublic
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: _isPublic
                              ? Center(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Public Account',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Your profile is discoverable by other Digital Share users in search.\n\nAnyone can search by name, company, or job title and view your business card profile (Full Name, Company, Job Title, Profile Photo, and Share ID).',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (_isSaving)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),
              ],
            ),
    );
  }
}
