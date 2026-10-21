import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/api_config.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/pending_profile_photo_store.dart';
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
  final ProfileService? profileService;
  final ImagePicker? imagePicker;

  const ProfileScreen({
    super.key,
    this.initialProfile,
    this.profileService,
    this.imagePicker,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {
  late final ProfileService _profileService;
  late final ImagePicker _imagePicker;
  final AuthService _authService = AuthService();

  UserProfile? _profile;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;
  String _errorMessage = '';
  bool _hasModified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profileService = widget.profileService ?? ProfileService();
    _imagePicker = widget.imagePicker ?? ImagePicker();

    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
    } else {
      _fetchProfile();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLostDataAndUpload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLostDataAndUpload();
    }
  }

  /// Recovers profile photo if Android killed the application while the external
  /// camera app was active.
  Future<void> _checkLostDataAndUpload() async {
    if (_isUploadingPhoto || PendingProfilePhotoStore.isUploadInProgress) {
      return;
    }

    final pending = await PendingProfilePhotoStore.loadPendingCapture();
    if (pending == null) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] ProfileScreen: lost-data recovery attempted');
    }

    try {
      final LostDataResponse response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] ProfileScreen: lost-data recovery returned empty');
        }
        await PendingProfilePhotoStore.clear();
        return;
      }

      if (response.exception != null) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] ProfileScreen: lost-data recovery failed: ${response.exception?.message}');
        }
        await PendingProfilePhotoStore.clear();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.exception?.message ?? 'Failed to recover captured photo.'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      final recoveredFile = response.file ??
          (response.files != null && response.files!.isNotEmpty ? response.files!.first : null);

      if (recoveredFile == null) {
        await PendingProfilePhotoStore.clear();
        return;
      }

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] ProfileScreen: lost-data recovery succeeded: ${recoveredFile.path}');
      }

      await _processAndUploadFile(recoveredFile);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] ProfileScreen: lost-data recovery error: $e');
      }
      await PendingProfilePhotoStore.clear();
    }
  }

  Future<void> _processAndUploadFile(XFile xFile) async {
    if (_isUploadingPhoto || PendingProfilePhotoStore.isUploadInProgress) {
      return;
    }

    if (PendingProfilePhotoStore.lastUploadedPath == xFile.path) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] Skipping duplicate upload for path: ${xFile.path}');
      }
      await PendingProfilePhotoStore.clear();
      return;
    }

    final rawFile = File(xFile.path);
    if (!rawFile.existsSync()) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The captured image file could not be found. Please try again.'),
          ),
        );
      }
      return;
    }

    final fileSize = rawFile.lengthSync();
    if (fileSize == 0) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The captured image is empty (0 bytes). Please take another photo.'),
          ),
        );
      }
      return;
    }

    const maxPhotoSizeBytes = 5 * 1024 * 1024; // 5 MB
    if (fileSize > maxPhotoSizeBytes) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected image exceeds the 5 MB limit. Please select a smaller photo.'),
          ),
        );
      }
      return;
    }

    final extension = xFile.path.contains('.')
        ? xFile.path.split('.').last.toLowerCase()
        : 'jpg';
    String contentType = 'image/jpeg';
    if (extension == 'png') {
      contentType = 'image/png';
    } else if (extension == 'webp') {
      contentType = 'image/webp';
    } else if (extension == 'gif') {
      contentType = 'image/gif';
    } else if (extension != 'jpg' && extension != 'jpeg') {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unsupported image format ($extension). Please use JPEG, PNG, WebP, or GIF.'),
          ),
        );
      }
      return;
    }

    File uploadFile = rawFile;
    File? tempStagedFile;
    try {
      final tempDir = Directory.systemTemp.path;
      final stagedPath = '$tempDir/profile_photo_staged_${DateTime.now().millisecondsSinceEpoch}.$extension';
      tempStagedFile = rawFile.copySync(stagedPath);
      uploadFile = tempStagedFile;
    } catch (_) {
      uploadFile = rawFile;
    }

    setState(() {
      _isUploadingPhoto = true;
    });
    PendingProfilePhotoStore.markUploadInProgress(true);

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] ProfileScreen: upload starting');
      debugPrint('[ProfilePhotoFlow] HTTP method: POST');
      debugPrint('[ProfilePhotoFlow] endpoint path: ${ApiConfig.uploadProfilePhotoEndpoint}');
      debugPrint('[ProfilePhotoFlow] multipart field name: file');
    }

    try {
      final updatedProfile = await _profileService.uploadProfilePhoto(
        filePath: uploadFile.path,
        filename: xFile.name.isNotEmpty ? xFile.name : 'profile_photo.$extension',
        contentType: contentType,
      );

      PendingProfilePhotoStore.lastUploadedPath = xFile.path;
      await PendingProfilePhotoStore.clear();

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] ProfileScreen: upload success 200 OK');
        debugPrint('[ProfilePhotoFlow] returned profile photo URL: ${updatedProfile.profilePhotoUrl}');
      }

      final oldResolvedUrl = ApiConfig.resolveImageUrl(_profile?.profilePhotoUrl);
      if (oldResolvedUrl != null) {
        PaintingBinding.instance.imageCache.evict(NetworkImage(oldResolvedUrl));
      }

      if (!mounted) return;

      setState(() {
        _profile = updatedProfile;
        _hasModified = true;
        _isUploadingPhoto = false;
      });

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] displayed photo URL/reference: ${_profile?.profilePhotoUrl}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo uploaded successfully!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] ProfileScreen upload failure: ${e.statusCode} ${e.message}');
      }
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] ProfileScreen unexpected error: $e');
      }
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not update profile photo. Please try again.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      PendingProfilePhotoStore.markUploadInProgress(false);
      if (tempStagedFile != null && tempStagedFile.existsSync()) {
        try {
          tempStagedFile.deleteSync();
        } catch (_) {}
      }
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
                                Stack(
                                  alignment: Alignment.center,
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
                                if (_isUploadingPhoto)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (_isUploadingPhoto) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Uploading photo...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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
