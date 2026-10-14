import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/shared_profile.dart';
import '../../services/api_client.dart';
import '../../services/connection_service.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../widgets/contact_message_composer.dart';
import '../connections/availability_viewer_screen.dart';

class ScannedProfileScreen extends StatefulWidget {
  final SharedProfile profile;
  final IContactService? contactService;
  final ConnectionService? connectionService;
  final IContactCommunicationService? communicationService;

  const ScannedProfileScreen({
    super.key,
    required this.profile,
    this.contactService,
    this.connectionService,
    this.communicationService,
  });

  @override
  State<ScannedProfileScreen> createState() => _ScannedProfileScreenState();
}

class _ScannedProfileScreenState extends State<ScannedProfileScreen> {
  late final IContactService _contactService;
  late final ConnectionService _connectionService;

  bool _isSaving = false;
  String _activeAction = '';

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ContactService();
    _connectionService = widget.connectionService ?? ConnectionService();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleSaveToPhone() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _activeAction = 'phone';
    });

    try {
      final result = await _contactService.saveSharedProfileToPhone(widget.profile);
      if (result.isSuccess) {
        _showFeedback('Contact saved to your phone.');
      } else {
        _showFeedback(result.message, isError: true);
      }
    } catch (e) {
      _showFeedback('Failed to save contact to phone: ${e.toString()}', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _activeAction = '';
        });
      }
    }
  }

  Future<void> _handleSaveInDigitalShare() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _activeAction = 'app';
    });

    try {
      await _connectionService.saveConnection(widget.profile.shareId);
      _showFeedback('Saved in Digital Share.');
    } on ConflictException {
      _showFeedback('This profile is already saved in Digital Share.');
    } on ApiException catch (e) {
      _showFeedback(e.message, isError: true);
    } catch (_) {
      _showFeedback('Failed to save connection in Digital Share.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _activeAction = '';
        });
      }
    }
  }

  Future<void> _handleSaveBoth() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _activeAction = 'both';
    });

    bool appSuccess = false;
    bool appAlreadySaved = false;
    String? appErrorMessage;

    // 1. Attempt Save in Digital Share
    try {
      await _connectionService.saveConnection(widget.profile.shareId);
      appSuccess = true;
    } on ConflictException {
      appAlreadySaved = true;
    } on ApiException catch (e) {
      appErrorMessage = e.message;
    } catch (e) {
      appErrorMessage = 'Could not save in Digital Share.';
    }

    // 2. Attempt Save to Phone Contacts
    ContactSaveResult phoneResult;
    try {
      phoneResult = await _contactService.saveSharedProfileToPhone(widget.profile);
    } catch (e) {
      phoneResult = ContactSaveResult(
        status: ContactSaveStatus.failed,
        message: e.toString(),
      );
    }

    // 3. Transparent reporting of independent results
    if (appSuccess && phoneResult.isSuccess) {
      _showFeedback('Saved to Digital Share and your phone.');
    } else if (appSuccess && !phoneResult.isSuccess) {
      _showFeedback('Saved in Digital Share, but not to phone contacts (${phoneResult.message}).', isError: true);
    } else if (appAlreadySaved && phoneResult.isSuccess) {
      _showFeedback('Already saved in Digital Share. Contact saved to your phone.');
    } else if (appAlreadySaved && !phoneResult.isSuccess) {
      _showFeedback('Already saved in Digital Share, but not to phone contacts.', isError: true);
    } else if (!appSuccess && phoneResult.isSuccess) {
      _showFeedback('Contact saved to your phone, but failed in Digital Share (${appErrorMessage ?? 'Error'}).', isError: true);
    } else {
      _showFeedback(
        'Failed to save: ${appErrorMessage ?? 'Digital Share error'} | ${phoneResult.message}',
        isError: true,
      );
    }

    if (mounted) {
      setState(() {
        _isSaving = false;
        _activeAction = '';
      });
    }
  }

  Widget _buildContactTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String? value,
  }) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
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
                  value.trim(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
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
    final profile = widget.profile;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned Digital Card'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
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
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: ApiConfig.resolveImageUrl(profile.profilePhotoUrl) != null
                        ? NetworkImage(ApiConfig.resolveImageUrl(profile.profilePhotoUrl)!)
                        : null,
                    onBackgroundImageError: ApiConfig.resolveImageUrl(profile.profilePhotoUrl) != null
                        ? (_, _) {}
                        : null,
                    child: ApiConfig.resolveImageUrl(profile.profilePhotoUrl) == null
                        ? Icon(
                            Icons.person,
                            size: 48,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile.displayName,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (profile.jobTitle != null && profile.jobTitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      profile.company != null && profile.company!.isNotEmpty
                          ? '${profile.jobTitle} • ${profile.company}'
                          : profile.jobTitle!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        profile.bio!,
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
            const SizedBox(height: 20),

            // Contact Info Details
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contact Details',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(height: 20),
                    _buildContactTile(
                      context: context,
                      icon: Icons.email_outlined,
                      label: 'Email',
                      value: profile.email,
                    ),
                    _buildContactTile(
                      context: context,
                      icon: Icons.phone_outlined,
                      label: 'Phone Number',
                      value: profile.phoneNumber,
                    ),
                    _buildContactTile(
                      context: context,
                      icon: Icons.language_outlined,
                      label: 'Website',
                      value: profile.website,
                    ),
                    _buildContactTile(
                      context: context,
                      icon: Icons.location_on_outlined,
                      label: 'Address',
                      value: profile.address,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // FOLLOW UP COMMUNICATION SECTION
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ContactMessageComposer.fromSharedProfile(
                  profile: profile,
                  sectionTitle: 'FOLLOW UP',
                  showAddToContacts: false,
                  communicationService: widget.communicationService,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // PHASE 4 CONTACT EXCHANGE ACTIONS
            Text(
              'Save Contact',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 1. Primary Hero Action: Save Both
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _handleSaveBoth,
                icon: _isSaving && _activeAction == 'both'
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.done_all_rounded),
                label: Text(
                  _isSaving && _activeAction == 'both' ? 'Saving...' : 'Save Both',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Secondary Actions Row
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isSaving ? null : _handleSaveToPhone,
                    icon: _isSaving && _activeAction == 'phone'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.phone_android_rounded, size: 20),
                    label: const Text('Save to Phone'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isSaving ? null : _handleSaveInDigitalShare,
                    icon: _isSaving && _activeAction == 'app'
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bookmark_add_outlined, size: 20),
                    label: const Text('Save in App'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // View Availability Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AvailabilityViewerScreen(
                        targetUserId: widget.profile.shareId,
                        userName: widget.profile.displayName,
                        userPhotoUrl: widget.profile.profilePhotoUrl,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.event_available_rounded, size: 20),
                label: const Text('View Availability'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Done / Return Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Done'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
