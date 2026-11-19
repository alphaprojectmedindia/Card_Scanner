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
import '../connections/saved_contacts_screen.dart';
import '../meetings/meetings_screen.dart';
import '../profile/digital_card_screen.dart';
import '../profile/profile_screen.dart';
import '../scan/business_card_scan_screen.dart';
import '../scan/create_qr_screen.dart';
import '../scan/qr_scanner_screen.dart';
import '../profile/availability_settings_screen.dart';
import '../../services/pending_card_capture_store.dart';
import '../../services/pending_profile_photo_store.dart';
import '../../services/onboarding_tutorial_service.dart';
import '../../services/secure_storage_service.dart';
import '../../widgets/custom_bottom_navigation_bar.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../../widgets/onboarding_tutorial_overlay.dart';

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

  // GlobalKeys for 11-Step Onboarding Tutorial
  final GlobalKey _step1HomeKey = GlobalKey();
  final GlobalKey _step2ScanKey = GlobalKey();
  final GlobalKey _step3ConnectionsKey = GlobalKey();
  final GlobalKey _step4FavoritesKey = GlobalKey();
  final GlobalKey _step5DigitalCardKey = GlobalKey();
  final GlobalKey _step6QrKey = GlobalKey();
  final GlobalKey _step7MeetingsKey = GlobalKey();
  final GlobalKey _step8AvailabilityKey = GlobalKey();
  final GlobalKey _step9SharedKey = GlobalKey();
  final GlobalKey _step10ProfileKey = GlobalKey();

  bool _isTutorialActive = false;
  int _currentTutorialStep = 0;

  List<OnboardingStepData> get _tutorialSteps => [
        OnboardingStepData(
          stepNumber: 1,
          heading: 'Welcome and Home Dashboard',
          description:
              'Welcome to Digital Share! Your central hub to monitor your network, track card counters, access quick actions, and navigate all features seamlessly.',
          targetKey: _step1HomeKey,
          icon: Icons.dashboard_rounded,
        ),
        OnboardingStepData(
          stepNumber: 2,
          heading: 'Business Card Scanner',
          description:
              'Scan physical business cards instantly using your camera or gallery. AI OCR extracts details accurately so you can review and edit before saving.',
          targetKey: _step2ScanKey,
          icon: Icons.badge_rounded,
        ),
        OnboardingStepData(
          stepNumber: 3,
          heading: 'My Connections',
          description:
              'All your saved business cards and connections are stored here. View complete contact details, search by personal memories, and initiate quick calls or emails.',
          targetKey: _step3ConnectionsKey,
          icon: Icons.people_alt_outlined,
        ),
        OnboardingStepData(
          stepNumber: 4,
          heading: 'Favorites and Contact Organization',
          description:
              'Star important contacts as favorites for instant access. Organize your network effortlessly so your key relationships are always at your fingertips.',
          targetKey: _step4FavoritesKey,
          icon: Icons.star_rounded,
        ),
        OnboardingStepData(
          stepNumber: 5,
          heading: 'My Digital Card',
          description:
              'Your personal digital business card. Share your live contact details, title, company, and customized QR code with others in seconds.',
          targetKey: _step5DigitalCardKey,
          icon: Icons.qr_code_2_rounded,
        ),
        OnboardingStepData(
          stepNumber: 6,
          heading: 'QR Generator and QR Scanner',
          description:
              'Generate customized QR codes for websites, Wi-Fi networks, contact info, and locations, or scan any standard QR code around you. Tap Next to tour the QR Generator.',
          targetKey: _step6QrKey,
          icon: Icons.qr_code_scanner_rounded,
        ),
        OnboardingStepData(
          stepNumber: 7,
          heading: 'Meetings',
          description:
              'Keep track of upcoming meetings, pending meeting requests, and your scheduling history. Seamlessly connected with your availability.',
          targetKey: _step7MeetingsKey,
          icon: Icons.calendar_today_rounded,
        ),
        OnboardingStepData(
          stepNumber: 8,
          heading: 'Availability',
          description:
              'Configure your weekly working hours and timezone settings so your connections know exactly when you are available to meet.',
          targetKey: _step8AvailabilityKey,
          icon: Icons.schedule_rounded,
        ),
        OnboardingStepData(
          stepNumber: 9,
          heading: 'Shared Items',
          description:
              'View digital business cards and contact items shared with you across Digital Share, organized and accessible at any time.',
          targetKey: _step9SharedKey,
          icon: Icons.share_rounded,
        ),
        OnboardingStepData(
          stepNumber: 10,
          heading: 'Profile and Settings',
          description:
              'View and update your personal information, job title, company, address, bio, and appearance preferences, or sign out securely.',
          targetKey: _step10ProfileKey,
          icon: Icons.person_outline_rounded,
        ),
        const OnboardingStepData(
          stepNumber: 11,
          heading: 'Finish Tour',
          description:
              "You're all set! You are ready to scan physical cards, connect with professionals, schedule meetings, and share your digital card.",
          targetKey: null,
          icon: Icons.check_circle_rounded,
        ),
      ];

  void _startOnboardingTour() {
    setState(() {
      _isTutorialActive = true;
      _currentTutorialStep = 0;
    });
  }

  Future<void> _endTutorial() async {
    setState(() {
      _isTutorialActive = false;
    });
    final userId = _profile?.id ?? await SecureStorageService().getUserId();
    await OnboardingTutorialService.instance.markCompleted(userId);
  }

  Future<void> _finishTutorial() async {
    setState(() {
      _isTutorialActive = false;
    });
    final userId = _profile?.id ?? await SecureStorageService().getUserId();
    await OnboardingTutorialService.instance.markCompleted(userId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You're all set! Welcome to Digital Share."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _checkFirstTimeTutorial() async {
    final userId = _profile?.id ?? await SecureStorageService().getUserId();
    final shouldShow =
        await OnboardingTutorialService.instance.shouldShowTutorial(userId);
    if (shouldShow && mounted && !_isTutorialActive) {
      _startOnboardingTour();
    }
  }

  void _onTourStartRequested() {
    if (OnboardingTutorialService.instance.shouldStartTourNotifier.value) {
      OnboardingTutorialService.instance.shouldStartTourNotifier.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startOnboardingTour();
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? ProfileService();
    _connectionService = widget.connectionService ?? ConnectionService();
    _importedContactService =
        widget.importedContactService ?? ImportedContactService();

    OnboardingTutorialService.instance.shouldStartTourNotifier
        .addListener(_onTourStartRequested);

    if (widget.initialProfile != null) {
      _profile = widget.initialProfile;
      _loadCounts();
    }

    // 1. Load locally saved dashboard information immediately (offline-first)
    _loadLocalDashboardData();

    // 2. Refresh from backend when network connectivity is available
    _refreshRemoteDashboardData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingCardCapture();
      _checkPendingProfilePhoto();
      _checkFirstTimeTutorial();
    });
  }

  @override
  void dispose() {
    OnboardingTutorialService.instance.shouldStartTourNotifier
        .removeListener(_onTourStartRequested);
    super.dispose();
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
    if (index == 0) {
      setState(() {
        _currentIndex = 0;
      });
      return;
    }

    if (index == 1) {
      // Saved Contacts Tab: Open unified saved contacts screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SavedContactsScreen(
            importedContactService: _importedContactService,
            connectionService: _connectionService,
          ),
        ),
      ).then((_) {
        _loadCounts();
        _loadDashboardData();
      });
      return;
    }

    if (index == 2) {
      // Centre Scan Tab: Open Scan choices screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BusinessCardScanScreen()),
      ).then((_) {
        _loadCounts();
        _loadDashboardData();
      });
      return;
    }

    if (index == 3) {
      // Meetings Tab: Open meetings screen
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MeetingsScreen()),
      ).then((_) => _loadDashboardData());
      return;
    }

    if (index == 4) {
      // Profile Tab: Open profile screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(initialProfile: _profile),
        ),
      ).then((result) {
        if (result == true) {
          _loadDashboardData();
        } else if (result is Map && result['startTour'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _startOnboardingTour();
          });
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
            key: const Key('home_help_tour_button'),
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: 'Interactive Tour',
            onPressed: _startOnboardingTour,
          ),
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
      body: Stack(
        children: [
          RefreshIndicator(
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

                  // Step 1 Target: Welcome Header
                  KeyedSubtree(
                    key: _step1HomeKey,
                    child: Container(
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

                // Step 2 Target: Business Card Scanner
                KeyedSubtree(
                  key: _step2ScanKey,
                  child: Card(
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

                // Step 5 Target: My Digital Card
                KeyedSubtree(
                  key: _step5DigitalCardKey,
                  child: Card(
                    key: const Key('home_my_digital_card_card'),
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 6 Target: QR Generator and QR Scanner
                KeyedSubtree(
                  key: _step6QrKey,
                  child: Card(
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
                      onTap: () async {
                        if (_isTutorialActive && _currentTutorialStep == 5) {
                          setState(() {
                            _isTutorialActive = false;
                          });
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  const CreateQrScreen(autoStartTour: true),
                            ),
                          );
                          if (mounted) {
                            setState(() {
                              _currentTutorialStep = 6;
                              _isTutorialActive = true;
                            });
                          }
                        } else {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CreateQrScreen(),
                            ),
                          );
                        }
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 7 Target: Meetings
                KeyedSubtree(
                  key: _step7MeetingsKey,
                  child: Card(
                    key: const Key('home_meetings_card'),
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 8 Target: Availability
                KeyedSubtree(
                  key: _step8AvailabilityKey,
                  child: Card(
                    key: const Key('home_availability_card'),
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
                            builder: (_) => const AvailabilitySettingsScreen(),
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
                                Icons.schedule_rounded,
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
                                    'Availability',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Configure your schedule and meeting preferences',
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

                // Step 3 Target: My Connections
                KeyedSubtree(
                  key: _step3ConnectionsKey,
                  child: Card(
                    key: const Key('home_my_connections_card'),
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
                            builder: (_) => const ConnectionsScreen(initialTab: 1),
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
                                    'Find all your cards and connections',
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 4 Target: Favorites and Contact Organization
                KeyedSubtree(
                  key: _step4FavoritesKey,
                  child: Card(
                    key: const Key('home_favorites_card'),
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
                                color: Colors.amber.shade100,
                                borderRadius: AppSpacing.radiusMd,
                              ),
                              child: const Icon(
                                Icons.star_rounded,
                                size: 26,
                                color: Color(0xFFD97706),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Favorites & Saved',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mark important cards as favorites for quick access',
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 9 Target: Shared Items
                KeyedSubtree(
                  key: _step9SharedKey,
                  child: Card(
                    key: const Key('home_shared_items_card'),
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
                            builder: (_) => const ConnectionsScreen(initialTab: 0),
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
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: AppSpacing.radiusMd,
                              ),
                              child: Icon(
                                Icons.share_outlined,
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
                                    'Shared Items',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'View cards and items shared with you',
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
                ),
                const SizedBox(height: AppSpacing.md),

                // Step 10 Target: Profile and Settings
                KeyedSubtree(
                  key: _step10ProfileKey,
                  child: Card(
                    key: const Key('home_my_profile_card'),
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
                        final result = await Navigator.of(context).push<dynamic>(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProfileScreen(initialProfile: _profile),
                          ),
                        );
                        if (result == true) {
                          _loadDashboardData();
                        } else if (result is Map && result['startTour'] == true) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _startOnboardingTour();
                          });
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
                                Icons.settings_outlined,
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
                                    'Explore your profile and settings',
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
                ),

                // Footer Medindia4u.com Branding
                const SizedBox(height: AppSpacing.lg),
                const MedindiaBrandingFooter(showDivider: true),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        ),

        // Interactive Onboarding Tutorial Overlay
        if (_isTutorialActive)
          OnboardingTutorialOverlay(
            steps: _tutorialSteps,
            initialStep: _currentTutorialStep,
            onFinish: _finishTutorial,
            onEndTour: _endTutorial,
            onStepChanged: (newStep) async {
              if (_currentTutorialStep == 5 && newStep == 6) {
                // User navigated from QR Generator step to launch QR Generator tour
                setState(() {
                  _isTutorialActive = false;
                });
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreateQrScreen(autoStartTour: true),
                  ),
                );
                if (mounted) {
                  setState(() {
                    _currentTutorialStep = 6; // Resume at Step 7 (Meetings)
                    _isTutorialActive = true;
                  });
                }
              } else {
                setState(() {
                  _currentTutorialStep = newStep;
                });
              }
            },
          ),
      ],
    ),
      bottomNavigationBar: CustomBottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onBottomNavTapped,
      ),
    );
  }
}
