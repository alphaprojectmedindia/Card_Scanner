import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/digital_share_logo.dart';
import '../../widgets/theme_selection_dialog.dart';
import '../auth/login_screen.dart';
import '../meetings/meetings_screen.dart';
import 'availability_settings_screen.dart';
import 'digital_card_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserProfile? initialProfile;

  const ProfileScreen({super.key, this.initialProfile});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();

  UserProfile? _profile;
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasModified = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
    } else {
      _fetchProfile();
    }
  }

  Future<void> _fetchProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final profile = await _profileService.getMyProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
        });
      }
    } on UnauthorizedException {
      await _authService.logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load profile. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to log out of Digital Share?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'System Default';
    }
  }

  Widget _buildInfoTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String? value,
  }) {
    final theme = Theme.of(context);
    final displayValue =
        (value != null && value.trim().isNotEmpty) ? value.trim() : 'Not provided';
    final isProvided = value != null && value.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: AppSpacing.radiusSm,
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  displayValue,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isProvided ? FontWeight.w600 : FontWeight.normal,
                    color: isProvided
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                    fontStyle: isProvided ? FontStyle.normal : FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Return modification status if popped
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_hasModified),
          ),
          actions: [
            if (_profile != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit Profile',
                onPressed: () async {
                  final updated = await Navigator.of(context).push<UserProfile?>(
                    MaterialPageRoute(
                      builder: (_) => EditProfileScreen(profile: _profile!),
                    ),
                  );
                  if (updated != null) {
                    setState(() {
                      _profile = updated;
                      _hasModified = true;
                    });
                  }
                },
              ),
          ],
        ),
        body: _isLoading && _profile == null
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage.isNotEmpty && _profile == null
                ? Center(
                    child: Padding(
                      padding: AppSpacing.dialogPadding,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(_errorMessage, textAlign: TextAlign.center),
                          const SizedBox(height: AppSpacing.lg),
                          FilledButton.tonal(
                            onPressed: _fetchProfile,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _fetchProfile,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: AppSpacing.pagePadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Profile Header
                          Center(
                            child: Column(
                              children: [
                                CircleAvatar(
                                  radius: 48,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  backgroundImage: ApiConfig.resolveImageUrl(
                                              _profile?.profilePhotoUrl) !=
                                          null
                                      ? NetworkImage(ApiConfig.resolveImageUrl(
                                          _profile?.profilePhotoUrl)!)
                                      : null,
                                  onBackgroundImageError: ApiConfig.resolveImageUrl(
                                              _profile?.profilePhotoUrl) !=
                                          null
                                      ? (_, _) {}
                                      : null,
                                  child: ApiConfig.resolveImageUrl(
                                              _profile?.profilePhotoUrl) ==
                                          null
                                      ? Icon(
                                          Icons.person,
                                          size: 48,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  _profile?.displayName ?? 'User Profile',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_profile?.jobTitle != null &&
                                    _profile!.jobTitle!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _profile!.company != null &&
                                            _profile!.company!.isNotEmpty
                                        ? '${_profile!.jobTitle} at ${_profile!.company}'
                                        : _profile!.jobTitle!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // Actions Row
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit Profile'),
                                  onPressed: _profile == null
                                      ? null
                                      : () async {
                                          final updated = await Navigator.of(context)
                                              .push<UserProfile?>(
                                            MaterialPageRoute(
                                              builder: (_) => EditProfileScreen(
                                                  profile: _profile!),
                                            ),
                                          );
                                          if (updated != null) {
                                            setState(() {
                                              _profile = updated;
                                              _hasModified = true;
                                            });
                                          }
                                        },
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.qr_code_2_rounded),
                                  label: const Text('My Digital Card'),
                                  onPressed: _profile == null
                                      ? null
                                      : () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => DigitalCardScreen(
                                                  initialProfile: _profile),
                                            ),
                                          );
                                        },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // Profile Details Card
                          Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppSpacing.radiusLg,
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: AppSpacing.cardPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Contact Information',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const Divider(height: 20),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.person_outline,
                                    label: 'Full Name',
                                    value: _profile?.fullName,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.email_outlined,
                                    label: 'Email',
                                    value: _profile?.email,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.phone_outlined,
                                    label: 'Phone Number',
                                    value: _profile?.phoneNumber,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.work_outline,
                                    label: 'Job Title',
                                    value: _profile?.jobTitle,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.business_outlined,
                                    label: 'Company',
                                    value: _profile?.company,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.language_outlined,
                                    label: 'Website',
                                    value: _profile?.website,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.location_on_outlined,
                                    label: 'Address',
                                    value: _profile?.address,
                                  ),
                                  _buildInfoTile(
                                    context: context,
                                    icon: Icons.notes_outlined,
                                    label: 'Bio / About',
                                    value: _profile?.bio,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // Settings & Preferences Card
                          Text(
                            'Preferences & Settings',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Card(
                            elevation: 0,
                            color: theme.colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: AppSpacing.radiusLg,
                              side: BorderSide(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Column(
                              children: [
                                ListenableBuilder(
                                  listenable: ThemeController.instance,
                                  builder: (context, _) {
                                    final currentMode =
                                        ThemeController.instance.themeMode;
                                    return ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme
                                              .colorScheme.primaryContainer,
                                          borderRadius: AppSpacing.radiusSm,
                                        ),
                                        child: Icon(
                                          Icons.palette_outlined,
                                          color: theme.colorScheme.primary,
                                          size: 20,
                                        ),
                                      ),
                                      title: const Text(
                                        'Appearance',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                          _getThemeModeLabel(currentMode)),
                                      trailing: const Icon(
                                          Icons.chevron_right_rounded),
                                      onTap: () =>
                                          ThemeSelectionDialog.show(context),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.secondaryContainer,
                                      borderRadius: AppSpacing.radiusSm,
                                    ),
                                    child: Icon(
                                      Icons.schedule_rounded,
                                      color: theme.colorScheme.secondary,
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'Availability',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: const Text('Schedule, timezone & meeting requests'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AvailabilitySettingsScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const Divider(height: 1),
                                ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.tertiaryContainer,
                                      borderRadius: AppSpacing.radiusSm,
                                    ),
                                    child: Icon(
                                      Icons.calendar_month_outlined,
                                      color: theme.colorScheme.tertiary,
                                      size: 20,
                                    ),
                                  ),
                                  title: const Text(
                                    'Meetings',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: const Text('Upcoming, requests & history'),
                                  trailing: const Icon(Icons.chevron_right_rounded),
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const MeetingsScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),

                          // Logout Action (Visually Distinct Destructive Option)
                          OutlinedButton.icon(
                            icon: Icon(
                              Icons.logout_rounded,
                              color: theme.colorScheme.error,
                            ),
                            label: Text(
                              'Sign Out',
                              style: TextStyle(
                                color: theme.colorScheme.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: theme.colorScheme.error.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.radiusMd,
                              ),
                            ),
                            onPressed: _handleLogout,
                          ),
                          const SizedBox(height: AppSpacing.xxl),

                          // App Branding & Version Footer
                          Center(
                            child: Column(
                              children: [
                                const DigitalShareLogo(
                                  size: 36,
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  'Digital Share',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Smart Contact & Availability Sharing • v1.0.0',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxxl),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}
