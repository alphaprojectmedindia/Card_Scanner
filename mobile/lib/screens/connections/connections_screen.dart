import 'package:flutter/material.dart';
import '../../config/api_config.dart';
import '../../models/imported_contact.dart';
import '../../models/saved_connection.dart';
import '../../services/api_client.dart';
import '../../services/connection_service.dart';
import '../../services/imported_contact_service.dart';
import '../scan/scanned_profile_screen.dart';
import 'imported_contact_details_screen.dart';
import '../../widgets/medindia_branding_footer.dart';

class ConnectionsScreen extends StatefulWidget {
  final ConnectionService? connectionService;
  final ImportedContactService? importedContactService;
  final int initialTab;

  const ConnectionsScreen({
    super.key,
    this.connectionService,
    this.importedContactService,
    this.initialTab = 0,
  });

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late final ConnectionService _connectionService;
  late final ImportedContactService _importedContactService;

  late int _selectedTab; // 0: Digital Share, 1: Business Cards

  // Digital Share Connections state
  List<SavedConnection> _connections = [];
  bool _isLoadingConnections = false;
  String _connectionsError = '';
  String _digitalSearchQuery = '';

  // Imported Business Cards state
  List<ImportedContact> _importedContacts = [];
  bool _isLoadingImported = false;
  bool _hasLoadedImported = false;
  String _importedError = '';
  String _businessCardSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _connectionService = widget.connectionService ?? ConnectionService();
    _importedContactService =
        widget.importedContactService ?? ImportedContactService();
    _selectedTab = widget.initialTab;
    if (_selectedTab == 1) {
      _loadImportedContacts();
    } else {
      _loadConnections();
    }
  }

  Future<void> _loadConnections() async {
    setState(() {
      _isLoadingConnections = true;
      _connectionsError = '';
    });

    try {
      final connections = await _connectionService.getConnections();
      if (mounted) {
        setState(() {
          _connections = connections;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _connectionsError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _connectionsError = 'Failed to load connections. Pull to refresh.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingConnections = false;
        });
      }
    }
  }

  Future<void> _loadImportedContacts() async {
    setState(() {
      _isLoadingImported = true;
      _importedError = '';
    });

    try {
      final contacts = await _importedContactService.getContacts();
      if (mounted) {
        setState(() {
          _importedContacts = contacts;
          _hasLoadedImported = true;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _importedError = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _importedError = 'Failed to load business cards. Pull to refresh.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingImported = false;
        });
      }
    }
  }

  Future<void> _handleDeleteConnection(SavedConnection connection) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Connection'),
        content: Text('Remove ${connection.displayName} from your saved connections?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _connectionService.deleteConnection(connection.shareId);
      setState(() {
        _connections.removeWhere((c) => c.shareId == connection.shareId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${connection.displayName}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to remove connection.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteImportedContact(ImportedContact contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Business Card'),
        content: Text('Delete ${contact.displayName} from your saved business cards?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _importedContactService.deleteContact(contact.id);
      setState(() {
        _importedContacts.removeWhere((c) => c.id == contact.id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${contact.displayName}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to delete business card.'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  List<SavedConnection> get _filteredConnections {
    if (_digitalSearchQuery.trim().isEmpty) {
      return _connections;
    }
    final query = _digitalSearchQuery.toLowerCase().trim();
    return _connections.where((c) {
      final name = c.fullName.toLowerCase();
      final company = (c.company ?? '').toLowerCase();
      final job = (c.jobTitle ?? '').toLowerCase();
      final email = (c.email ?? '').toLowerCase();
      return name.contains(query) ||
          company.contains(query) ||
          job.contains(query) ||
          email.contains(query);
    }).toList();
  }

  List<ImportedContact> get _filteredImportedContacts {
    if (_businessCardSearchQuery.trim().isEmpty) {
      return _importedContacts;
    }
    final query = _businessCardSearchQuery.toLowerCase().trim();
    return _importedContacts.where((c) {
      final name = (c.fullName ?? '').toLowerCase();
      final company = (c.company ?? '').toLowerCase();
      final job = (c.jobTitle ?? '').toLowerCase();
      final phones = c.phoneNumbers.map((p) => p.number.toLowerCase()).join(' ');
      final emails = c.emailAddresses.map((e) => e.email.toLowerCase()).join(' ');
      final address = (c.address ?? '').toLowerCase();
      final memory = (c.effectiveMemory ?? '').toLowerCase();
      return name.contains(query) ||
          company.contains(query) ||
          job.contains(query) ||
          phones.contains(query) ||
          emails.contains(query) ||
          address.contains(query) ||
          memory.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Connections',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Segmented Tabs: Digital Share vs Business Cards
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                key: const Key('connections_segmented_button'),
                segments: const [
                  ButtonSegment<int>(
                    value: 0,
                    label: Text('Digital Share'),
                    icon: Icon(Icons.qr_code_rounded),
                  ),
                  ButtonSegment<int>(
                    value: 1,
                    label: Text('Business Cards'),
                    icon: Icon(Icons.badge_outlined),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedTab = newSelection.first;
                  });
                  if (_selectedTab == 1 &&
                      _importedContacts.isEmpty &&
                      !_hasLoadedImported) {
                    _loadImportedContacts();
                  }
                },
              ),
            ),
          ),

          // Body Content depending on selected tab
          Expanded(
            child: _selectedTab == 0
                ? _buildDigitalShareView(theme)
                : _buildBusinessCardsView(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildDigitalShareView(ThemeData theme) {
    final displayed = _filteredConnections;

    return RefreshIndicator(
      onRefresh: _loadConnections,
      child: Column(
        children: [
          if (_connections.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: TextField(
                key: const Key('digital_connections_search_field'),
                onChanged: (val) {
                  setState(() {
                    _digitalSearchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search connections...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _digitalSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            setState(() {
                              _digitalSearchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

          Expanded(
            child: _isLoadingConnections && _connections.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _connectionsError.isNotEmpty && _connections.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 54, color: theme.colorScheme.error),
                              const SizedBox(height: 12),
                              Text(_connectionsError,
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton.tonal(
                                onPressed: _loadConnections,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _connections.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.4),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.people_alt_outlined,
                                            size: 56,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'No Connections Yet',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Scan another person\'s Digital Share QR code to save their live digital card here.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : displayed.isEmpty
                            ? ListView(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Center(
                                      child: Text(
                                        'No connections matching "$_digitalSearchQuery"',
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                itemCount: displayed.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final connection = displayed[index];
                                  return Card(
                                    elevation: 0,
                                    color:
                                        theme.colorScheme.surfaceContainerLow,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => ScannedProfileScreen(
                                              profile:
                                                  connection.toSharedProfile(),
                                            ),
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: theme
                                                  .colorScheme.primaryContainer,
                                              backgroundImage: ApiConfig
                                                          .resolveImageUrl(
                                                              connection
                                                                  .profilePhotoUrl) !=
                                                      null
                                                  ? NetworkImage(
                                                      ApiConfig.resolveImageUrl(
                                                          connection
                                                              .profilePhotoUrl)!)
                                                  : null,
                                              onBackgroundImageError: ApiConfig
                                                          .resolveImageUrl(
                                                              connection
                                                                  .profilePhotoUrl) !=
                                                      null
                                                  ? (_, _) {}
                                                  : null,
                                              child: ApiConfig.resolveImageUrl(
                                                          connection
                                                              .profilePhotoUrl) ==
                                                      null
                                                  ? Icon(
                                                      Icons.person,
                                                      color: theme
                                                          .colorScheme.primary,
                                                      size: 28,
                                                    )
                                                  : null,
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    connection.displayName,
                                                    style: theme
                                                        .textTheme.titleMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (connection.jobTitle !=
                                                          null &&
                                                      connection.jobTitle!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      connection.company !=
                                                                  null &&
                                                              connection
                                                                  .company!
                                                                  .isNotEmpty
                                                          ? '${connection.jobTitle} • ${connection.company}'
                                                          : connection
                                                              .jobTitle!,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .primary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                  if (connection.email !=
                                                          null &&
                                                      connection.email!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      connection.email!,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme.colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                color: theme.colorScheme.error
                                                    .withValues(alpha: 0.8),
                                                size: 22,
                                              ),
                                              tooltip: 'Remove connection',
                                              onPressed: () =>
                                                  _handleDeleteConnection(
                                                      connection),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
          const MedindiaBrandingFooter(showDivider: true),
        ],
      ),
    );
  }

  Widget _buildBusinessCardsView(ThemeData theme) {
    final displayed = _filteredImportedContacts;

    return RefreshIndicator(
      onRefresh: _loadImportedContacts,
      child: Column(
        children: [
          if (_importedContacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: TextField(
                key: const Key('business_cards_search_field'),
                onChanged: (val) {
                  setState(() {
                    _businessCardSearchQuery = val;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search business cards...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _businessCardSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            setState(() {
                              _businessCardSearchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),

          Expanded(
            child: _isLoadingImported && _importedContacts.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _importedError.isNotEmpty && _importedContacts.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 54, color: theme.colorScheme.error),
                              const SizedBox(height: 12),
                              Text(_importedError,
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton.tonal(
                                onPressed: _loadImportedContacts,
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _importedContacts.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .secondaryContainer
                                                .withValues(alpha: 0.4),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.badge_outlined,
                                            size: 56,
                                            color: theme.colorScheme.secondary,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'No Business Cards Yet',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Scan physical business cards using the scanner to save them here.',
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : displayed.isEmpty
                            ? ListView(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Center(
                                      child: Text(
                                        'No cards matching "$_businessCardSearchQuery"',
                                        style: theme.textTheme.bodyLarge
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 8),
                                itemCount: displayed.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemBuilder: (context, index) {
                                  final contact = displayed[index];
                                  final phone = contact.primaryPhone;
                                  final email = contact.primaryEmail;

                                  return Card(
                                    key: Key('imported_card_${contact.id}'),
                                    elevation: 0,
                                    color:
                                        theme.colorScheme.surfaceContainerLow,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(
                                        color: theme.colorScheme.outlineVariant
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                                        final deleted = await Navigator.of(context)
                                            .push<bool>(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                ImportedContactDetailsScreen(
                                              contact: contact,
                                              contactService:
                                                  _importedContactService,
                                            ),
                                          ),
                                        );
                                        if (deleted == true && mounted) {
                                          setState(() {
                                            _importedContacts.removeWhere(
                                                (c) => c.id == contact.id);
                                          });
                                        } else if (mounted) {
                                          _loadImportedContacts();
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: theme
                                                  .colorScheme.secondaryContainer,
                                              child: Text(
                                                contact.initials,
                                                style: TextStyle(
                                                  color: theme.colorScheme
                                                      .onSecondaryContainer,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    contact.displayName,
                                                    style: theme
                                                        .textTheme.titleMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  if (contact.jobTitle != null &&
                                                          contact.jobTitle!
                                                              .isNotEmpty ||
                                                      contact.company != null &&
                                                          contact.company!
                                                              .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      [
                                                        if (contact.jobTitle !=
                                                                null &&
                                                            contact.jobTitle!
                                                                .isNotEmpty)
                                                          contact.jobTitle!,
                                                        if (contact.company !=
                                                                null &&
                                                            contact.company!
                                                                .isNotEmpty)
                                                          contact.company!,
                                                      ].join(' • '),
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .secondary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                  if (phone != null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      phone,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme.colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ] else if (email != null) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      email,
                                                      style: theme
                                                          .textTheme.bodySmall
                                                          ?.copyWith(
                                                        color: theme.colorScheme
                                                            .onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                  if (contact.effectiveMemory != null &&
                                                      contact.effectiveMemory!.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFE8F1FC),
                                                        borderRadius:
                                                            BorderRadius.circular(6),
                                                        border: Border.all(
                                                          color: const Color(0xFFB9D5F8),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons.lightbulb_outline_rounded,
                                                            size: 13,
                                                            color: Color(0xFF1E5BB0),
                                                          ),
                                                          const SizedBox(width: 5),
                                                          Flexible(
                                                            child: Text(
                                                              'Memory: ${contact.effectiveMemory!}',
                                                              style: const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight.w500,
                                                                color:
                                                                    Color(0xFF1E5BB0),
                                                              ),
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              icon: Icon(
                                                Icons.delete_outline_rounded,
                                                color: theme.colorScheme.error
                                                    .withValues(alpha: 0.8),
                                                size: 22,
                                              ),
                                              tooltip: 'Delete business card',
                                              onPressed: () =>
                                                  _handleDeleteImportedContact(
                                                      contact),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
          ),
          const MedindiaBrandingFooter(showDivider: true),
        ],
      ),
    );
  }
}
