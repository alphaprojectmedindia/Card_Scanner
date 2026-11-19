import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/api_config.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../auth/login_screen.dart';

class DigitalCardScreen extends StatefulWidget {
  final UserProfile? initialProfile;

  const DigitalCardScreen({super.key, this.initialProfile});

  @override
  State<DigitalCardScreen> createState() => _DigitalCardScreenState();
}

class _DigitalCardScreenState extends State<DigitalCardScreen> {
  final ProfileService _profileService = ProfileService();
  final AuthService _authService = AuthService();

  UserProfile? _profile;
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
    } else {
      _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
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
          _errorMessage = 'Failed to load card preview. Please pull to refresh.';
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

  Widget _buildContactRow({
    required BuildContext context,
    required IconData icon,
    required String text,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Digital Card'),
      ),
      body: _isLoading && _profile == null
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty && _profile == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_errorMessage, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _loadProfile,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Column(
                      children: [
                        // Digital Card Container
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.surfaceContainerHigh,
                                theme.colorScheme.surfaceContainerLowest,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Top Badge Bar
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'DIGITAL SHARE',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.nfc_rounded,
                                      size: 20,
                                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Profile Avatar
                                CircleAvatar(
                                  radius: 44,
                                  backgroundColor: theme.colorScheme.primaryContainer,
                                  backgroundImage: ApiConfig.resolveImageUrl(_profile?.profilePhotoUrl) != null
                                      ? NetworkImage(ApiConfig.resolveImageUrl(_profile?.profilePhotoUrl)!)
                                      : null,
                                  onBackgroundImageError: ApiConfig.resolveImageUrl(_profile?.profilePhotoUrl) != null
                                      ? (_, _) {}
                                      : null,
                                  child: ApiConfig.resolveImageUrl(_profile?.profilePhotoUrl) == null
                                      ? Icon(
                                          Icons.person,
                                          size: 44,
                                          color: theme.colorScheme.primary,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 16),

                                // Name
                                Text(
                                  _profile?.displayName ?? 'Digital Card',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),

                                // Title & Company
                                if (_profile?.jobTitle != null && _profile!.jobTitle!.isNotEmpty)
                                  Text(
                                    _profile!.jobTitle!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                if (_profile?.company != null && _profile!.company!.isNotEmpty)
                                  Text(
                                    _profile!.company!,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),

                                const Divider(height: 28),

                                // Real Dynamic QR Code Generation
                                if (_profile?.shareId != null && _profile!.shareId.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: QrImageView(
                                      data: ApiConfig.buildShareUrl(_profile!.shareId),
                                      version: QrVersions.auto,
                                      size: 180.0,
                                      eyeStyle: const QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: Color(0xFF0F172A),
                                      ),
                                      dataModuleStyle: const QrDataModuleStyle(
                                        dataModuleShape: QrDataModuleShape.square,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Scan to view my Digital Share card',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                ],

                                // Contact Details List
                                if (_profile?.email != null && _profile!.email.isNotEmpty)
                                  _buildContactRow(
                                    context: context,
                                    icon: Icons.email_outlined,
                                    text: _profile!.email,
                                  ),
                                if (_profile?.phoneNumber != null && _profile!.phoneNumber!.isNotEmpty)
                                  _buildContactRow(
                                    context: context,
                                    icon: Icons.phone_outlined,
                                    text: _profile!.phoneNumber!,
                                  ),
                                if (_profile?.website != null && _profile!.website!.isNotEmpty)
                                  _buildContactRow(
                                    context: context,
                                    icon: Icons.language_outlined,
                                    text: _profile!.website!,
                                  ),
                                if (_profile?.address != null && _profile!.address!.isNotEmpty)
                                  _buildContactRow(
                                    context: context,
                                    icon: Icons.location_on_outlined,
                                    text: _profile!.address!,
                                  ),

                                if (_profile?.bio != null && _profile!.bio!.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _profile!.bio!,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontStyle: FontStyle.italic,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const MedindiaBrandingFooter(showDivider: true),
                      ],
                    ),
                  ),
                ),
    );
  }
}
