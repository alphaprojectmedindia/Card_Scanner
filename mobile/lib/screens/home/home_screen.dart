import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/connection_service.dart';
import '../../services/imported_contact_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/digital_share_logo.dart';
import '../../widgets/theme_selection_dialog.dart';
import '../auth/login_screen.dart';
import '../connections/connections_screen.dart';
import '../meetings/meetings_screen.dart';
import '../profile/digital_card_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/business_card_scan_screen.dart';
import '../scan/create_qr_screen.dart';
import '../scan/qr_scanner_screen.dart';
import '../../services/pending_card_capture_store.dart';
import '../../services/pending_profile_photo_store.dart';

class HomeScreen extends StatefulWidget {
  final UserProfile? initialProfile;
  final ConnectionService? connectionService;
  final ImportedContactService? importedContactService;
  final ProfileService? profileService;

  const HomeScreen({
    super.key,
    this.initialProfile,
    this.connectionService,
    this.importedContactService,
    this.profileService,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ProfileService _profileService;
  final AuthService _authService = AuthService();
  late final ConnectionService _connectionService;
  late final ImportedContactService _importedContactService;

  UserProfile? _profile;
  bool _isRefreshing = false;
  String _syncStatusMessage = '';
  int _currentIndex = 0;

  int _digitalConnectionsCount = 0;
  int _businessCardsCount = 0;

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? ProfileService();
    _connectionService = widget.connectionService ?? ConnectionService();
    _importedContactService =
        widget.importedContactService ?? ImportedContactService();

    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
    }

    // 1. Load locally saved dashboard information immediately (offline-first)
    _loadLocalDashboardData();

    // 2. Refresh from backend when network connectivity is available
    _refreshRemoteDashboardData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingCardCapture();
      _checkPendingProfilePhoto();
    });
  }

  Future<void> _checkPendingCardCapture() async {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final pending = await PendingCardCaptureStore.loadPendingCapture();
    if (pending != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const BusinessCardScanScreen(),
        ),
      ).then((_) => _loadCounts());
    }
  }

  Future<void> _checkPendingProfilePhoto() async {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    final pending = await PendingProfilePhotoStore.loadPendingCapture();
    if (pending != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(initialProfile: _profile),
        ),
      ).then((modified) {
        if (modified == true) {
          _loadDashboardData();
        }
      });
    }
  }

  /// Immediately populates dashboard stats and profile from local disk storage.
  /// Does not perform any network calls and executes in milliseconds.
  Future<void> _loadLocalDashboardData() async {
    // 1. Immediately read locally saved business card count
    try {
      final localCards =
          await _importedContactService.localRepository.getContacts();
      if (mounted) {
        setState(() {
          _businessCardsCount = localCards.length;
        });
      }
    } catch (_) {}

    // 2. Immediately read locally cached user profile if initialProfile was not provided
    if (_profile == null) {
      try {
        final cached = await _profileService.getCachedProfile();
        if (cached != null && mounted) {
          setState(() {
            _profile = cached;
          });
        }
      } catch (_) {}
    }

    // 3. Immediately read locally cached digital connections count
    try {
      final cachedCount =
          await _connectionService.getCachedConnectionsCount();
      if (mounted && cachedCount > 0) {
        setState(() {
          _digitalConnectionsCount = cachedCount;
        });
      }
    } catch (_) {}
  }

  /// Refreshes dashboard data from the backend with bounded timeouts.
  /// If the backend is unavailable or times out, retains all local data and surfaces
  /// a subtle, non-intrusive status indicator with a retry action.
  Future<void> _refreshRemoteDashboardData({bool isUserTriggered = false}) async {
    if (_isRefreshing) return;

    if (mounted) {
      setState(() {
        _isRefreshing = true;
        if (isUserTriggered) {
          _syncStatusMessage = '';
        }
      });
    }

    try {
      // Query profile, connections, and contacts in parallel with 10s bounded timeout
      final profileFuture = _profileService
          .getMyProfile()
          .then<dynamic>((p) => p)
          .catchError((e) => e);

      final connsFuture = _connectionService
          .getConnections()
          .then<dynamic>((c) => c)
          .catchError((e) => e);

      final cardsFuture = _importedContactService
          .getContacts()
          .then<dynamic>((k) => k)
          .catchError((e) => e);

      final results = await Future.wait([profileFuture, connsFuture, cardsFuture]);

      if (!mounted) return;

      final profileResult = results[0];
      final connsResult = results[1];
      final cardsResult = results[2];

      // Handle session expiration
      if (profileResult is UnauthorizedException ||
          connsResult is UnauthorizedException) {
        await _authService.logout();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }

      bool hasNetworkError = false;

      if (profileResult is UserProfile) {
        _profile = profileResult;
      } else if (profileResult is Exception) {
        hasNetworkError = true;
      }

      if (connsResult is List) {
        _digitalConnectionsCount = connsResult.length;
      } else if (connsResult is Exception) {
        hasNetworkError = true;
      }

      if (cardsResult is List) {
        _businessCardsCount = cardsResult.length;
      } else if (cardsResult is Exception) {
        hasNetworkError = true;
      }

      setState(() {
        if (hasNetworkError) {
          _syncStatusMessage = isUserTriggered
              ? 'Could not connect to server. Displaying saved offline data.'
              : 'Offline — displaying local data.';
        } else {
          _syncStatusMessage = '';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _syncStatusMessage = 'Offline — displaying local data.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _loadDashboardData() async {
    await _loadLocalDashboardData();
    await _refreshRemoteDashboardData(isUserTriggered: true);
  }

  Future<void> _loadCounts() async {
    try {
      final conns = await _connectionService.getConnections();
      if (mounted) {
        setState(() {
          _digitalConnectionsCount = conns.length;
        });
      }
    } catch (_) {}

    try {
      final cards = await _importedContactService.getContacts();
      if (mounted) {
        setState(() {
          _businessCardsCount = cards.length;
        });
      }
    } catch (_) {}
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

  void _onBottomNavTapped(int index) {
    if (index == 1) {
      // Scan Tab: Open Scan choices screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BusinessCardScanScreen()),
      );
      return;
    }

    if (index == 2) {
      // Connections Tab: Open connections screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ConnectionsScreen()),
      ).then((_) => _loadCounts());
      return;
    }

    if (index == 3) {
      // Profile Tab: Open profile screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(initialProfile: _profile),
        ),
      ).then((modified) {
        if (modified == true) {
          _loadDashboardData();
        }
      });
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DigitalShareLogo(
              size: 28,
            ),
            SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'Digital Share',
                style: TextStyle(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Appearance',
            onPressed: () => ThemeSelectionDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshRemoteDashboardData(isUserTriggered: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Offline / Synchronization Status (Non-intrusive banner)
              if (_syncStatusMessage.isNotEmpty) ...[
                Container(
                  key: const Key('home_offline_status_banner'),
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs + 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: AppSpacing.radiusMd,
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _syncStatusMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_isRefreshing)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        TextButton(
                          key: const Key('home_retry_sync_button'),
                          onPressed: () =>
                              _refreshRemoteDashboardData(isUserTriggered: true),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('Retry'),
                        ),
                    ],
                  ),
                ),
              ],

              // Welcome Header
              Container(
                width: double.infinity,
                padding: AppSpacing.cardPadding,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: AppSpacing.radiusLg,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant,
                    width: 1.0,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome,',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _profile?.displayName ?? 'User',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    if (_profile?.jobTitle != null &&
                        _profile!.jobTitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _profile!.company != null && _profile!.company!.isNotEmpty
                            ? '${_profile!.jobTitle} • ${_profile!.company}'
                            : _profile!.jobTitle!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // Quick stats summary
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: AppSpacing.radiusSm,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ConnectionsScreen(),
                                ),
                              ).then((_) => _loadCounts());
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: AppSpacing.radiusSm,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.people_alt_outlined,
                                    size: 16,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      '$_digitalConnectionsCount Connections',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: InkWell(
                            borderRadius: AppSpacing.radiusSm,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ConnectionsScreen(),
                                ),
                              ).then((_) => _loadCounts());
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: AppSpacing.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: AppSpacing.radiusSm,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.badge_outlined,
                                    size: 16,
                                    color: theme.colorScheme.secondary,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      '$_businessCardsCount Cards',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Primary Quick Actions Header
                Text(
                  'Quick Actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Primary Action 1: Business Card Scanner
                Card(
                  key: const Key('home_business_card_scanner_card'),
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const BusinessCardScanScreen(),
                        ),
                      ).then((_) => _loadCounts());
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.badge_rounded,
                              size: 26,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Business Card Scanner',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Scan a physical business card',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Primary Action 2: Universal QR Scanner
                Card(
                  key: const Key('home_universal_qr_scanner_card'),
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QrScannerScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 26,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Universal QR Scanner',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Scan any QR code',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Primary Action 2: My Digital Card
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              DigitalCardScreen(initialProfile: _profile),
                        ),
                      );
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.qr_code_2_rounded,
                              size: 26,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Digital Card',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Show your QR code and contact card',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Primary Action: QR Generator (Universal QR Generator)
                Card(
                  key: const Key('home_qr_generator_card'),
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateQrScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.qr_code_rounded,
                              size: 26,
                              color: theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'QR Generator',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Create QR codes for links, Wi-Fi, contacts, location and more',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Create QR',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Primary Action 3: Meetings
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MeetingsScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.calendar_today_rounded,
                              size: 26,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Meetings',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'View requests and upcoming meetings',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),

                // Secondary Actions Header
                Text(
                  'Manage Contacts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Secondary Action 1: Connections
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ConnectionsScreen(),
                        ),
                      ).then((_) => _loadCounts());
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.people_alt_outlined,
                              size: 26,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Connections',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'View your saved Digital Share cards',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Secondary Action 2: My Profile
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.radiusLg,
                    side: BorderSide(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: AppSpacing.radiusLg,
                    onTap: () async {
                      final updated = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfileScreen(initialProfile: _profile),
                        ),
                      );
                      if (updated == true) {
                        _loadDashboardData();
                      }
                    },
                    child: Padding(
                      padding: AppSpacing.cardPadding,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: AppSpacing.radiusMd,
                            ),
                            child: Icon(
                              Icons.person_outline_rounded,
                              size: 26,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'My Profile',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'View & edit your contact details',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onBottomNavTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_rounded),
            selectedIcon: Icon(Icons.qr_code_scanner_rounded),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: 'Connections',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
