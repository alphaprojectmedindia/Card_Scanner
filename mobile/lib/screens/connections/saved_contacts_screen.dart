import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/imported_contact.dart';
import '../../models/saved_connection.dart';
import '../../models/shared_profile.dart';
import '../../services/connection_service.dart';
import '../../services/imported_contact_service.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../scan/business_card_scan_screen.dart';
import '../scan/qr_scanner_screen.dart';
import '../scan/scanned_profile_screen.dart';
import 'edit_imported_contact_screen.dart';
import 'imported_contact_details_screen.dart';

enum ContactSourceType {
  all,
  businessCard,
  qrScan,
}

class UnifiedContactModel {
  final String id;
  final ContactSourceType source;
  final String fullName;
  final String? jobTitle;
  final String? company;
  final String? phoneNumber;
  final String? email;
  final String? address;
  final String? website;
  final String? memory;
  final String? profilePhotoUrl;
  final String? shareId;
  final DateTime createdAt;
  final ImportedContact? rawImportedContact;
  final SavedConnection? rawConnection;

  const UnifiedContactModel({
    required this.id,
    required this.source,
    required this.fullName,
    this.jobTitle,
    this.company,
    this.phoneNumber,
    this.email,
    this.address,
    this.website,
    this.memory,
    this.profilePhotoUrl,
    this.shareId,
    required this.createdAt,
    this.rawImportedContact,
    this.rawConnection,
  });
}

class SavedContactsScreen extends StatefulWidget {
  final ImportedContactService? importedContactService;
  final ConnectionService? connectionService;
  final List<ImportedContact>? initialContacts;

  const SavedContactsScreen({
    super.key,
    this.importedContactService,
    this.connectionService,
    this.initialContacts,
  });

  @override
  State<SavedContactsScreen> createState() => _SavedContactsScreenState();
}

class _SavedContactsScreenState extends State<SavedContactsScreen> {
  late final ImportedContactService _importedContactService;
  late final ConnectionService _connectionService;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  ContactSourceType _selectedFilter = ContactSourceType.all;

  List<UnifiedContactModel> _allContacts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _importedContactService =
        widget.importedContactService ?? ImportedContactService();
    _connectionService = widget.connectionService ?? ConnectionService();
    _loadAllContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllContacts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    if (widget.initialContacts != null) {
      final combined = <UnifiedContactModel>[];
      for (final card in widget.initialContacts!) {
        final firstPhone =
            card.phoneNumbers.isNotEmpty ? card.phoneNumbers.first.number : null;
        final firstEmail =
            card.emailAddresses.isNotEmpty ? card.emailAddresses.first.email : null;
        final mem = card.rememberThisContact ?? card.personalRemark;

        combined.add(UnifiedContactModel(
          id: card.id,
          source: ContactSourceType.businessCard,
          fullName: card.fullName?.trim().isNotEmpty == true
              ? card.fullName!.trim()
              : 'Unnamed Business Card',
          jobTitle: card.jobTitle,
          company: card.company,
          phoneNumber: firstPhone,
          email: firstEmail,
          address: card.address,
          website: card.website,
          memory: mem,
          profilePhotoUrl: null,
          shareId: null,
          createdAt: card.createdAtUtc ?? DateTime.now(),
          rawImportedContact: card,
        ));
      }
      setState(() {
        _allContacts = combined;
        _isLoading = false;
      });
      return;
    }

    try {
      final List<UnifiedContactModel> combined = [];

      // 1. Fetch Imported Business Cards
      try {
        final cards = await _importedContactService.getContacts();
        for (final card in cards) {
          final firstPhone =
              card.phoneNumbers.isNotEmpty ? card.phoneNumbers.first.number : null;
          final firstEmail =
              card.emailAddresses.isNotEmpty ? card.emailAddresses.first.email : null;
          final mem = card.rememberThisContact ?? card.personalRemark;

          combined.add(UnifiedContactModel(
            id: card.id,
            source: ContactSourceType.businessCard,
            fullName: card.fullName?.trim().isNotEmpty == true
                ? card.fullName!.trim()
                : 'Unnamed Business Card',
            jobTitle: card.jobTitle,
            company: card.company,
            phoneNumber: firstPhone,
            email: firstEmail,
            address: card.address,
            website: card.website,
            memory: mem,
            profilePhotoUrl: null,
            shareId: null,
            createdAt: card.createdAtUtc ?? DateTime.now(),
            rawImportedContact: card,
          ));
        }
      } catch (e) {
        debugPrint('[SavedContacts] Error loading business cards: $e');
      }

      // 2. Fetch In-App QR Code / Digital Share Connections
      try {
        final connections = await _connectionService.getConnections();
        for (final conn in connections) {
          combined.add(UnifiedContactModel(
            id: conn.shareId,
            source: ContactSourceType.qrScan,
            fullName: conn.fullName.trim().isNotEmpty
                ? conn.fullName.trim()
                : 'Digital Share Connection',
            jobTitle: conn.jobTitle,
            company: conn.company,
            phoneNumber: conn.phoneNumber,
            email: conn.email,
            address: conn.address,
            website: conn.website,
            memory: null,
            profilePhotoUrl: conn.profilePhotoUrl,
            shareId: conn.shareId,
            createdAt: conn.savedAtUtc,
            rawConnection: conn,
          ));
        }
      } catch (e) {
        debugPrint('[SavedContacts] Error loading connections: $e');
      }

      // Sort newest first
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _allContacts = combined;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load saved contacts. Please pull to refresh.';
        });
      }
    }
  }

  List<UnifiedContactModel> get _filteredContacts {
    return _allContacts.where((contact) {
      // 1. Source Filter
      if (_selectedFilter == ContactSourceType.businessCard &&
          contact.source != ContactSourceType.businessCard) {
        return false;
      }
      if (_selectedFilter == ContactSourceType.qrScan &&
          contact.source != ContactSourceType.qrScan) {
        return false;
      }

      // 2. Search Query Filter
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();

      final matchesName = contact.fullName.toLowerCase().contains(q);
      final matchesCompany = contact.company?.toLowerCase().contains(q) ?? false;
      final matchesJob = contact.jobTitle?.toLowerCase().contains(q) ?? false;
      final matchesPhone = contact.phoneNumber?.toLowerCase().contains(q) ?? false;
      final matchesEmail = contact.email?.toLowerCase().contains(q) ?? false;
      final matchesAddress = contact.address?.toLowerCase().contains(q) ?? false;
      final matchesWebsite = contact.website?.toLowerCase().contains(q) ?? false;
      final matchesMemory = contact.memory?.toLowerCase().contains(q) ?? false;

      return matchesName ||
          matchesCompany ||
          matchesJob ||
          matchesPhone ||
          matchesEmail ||
          matchesAddress ||
          matchesWebsite ||
          matchesMemory;
    }).toList();
  }

  Future<void> _handleDeleteContact(UnifiedContactModel contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text(
          'Are you sure you want to permanently delete "${contact.fullName}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      if (contact.source == ContactSourceType.businessCard) {
        await _importedContactService.deleteContact(contact.id);
      } else if (contact.shareId != null) {
        await _connectionService.deleteConnection(contact.shareId!);
      }

      setState(() {
        _allContacts.removeWhere((c) => c.id == contact.id);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted "${contact.fullName}"'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete contact: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openContactDetails(UnifiedContactModel contact) {
    if (contact.source == ContactSourceType.businessCard &&
        contact.rawImportedContact != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ImportedContactDetailsScreen(
            contact: contact.rawImportedContact!,
            contactService: _importedContactService,
          ),
        ),
      ).then((_) => _loadAllContacts());
    } else if (contact.shareId != null) {
      final sharedProfile = contact.rawConnection?.toSharedProfile() ??
          SharedProfile(
            shareId: contact.shareId!,
            fullName: contact.fullName,
            phoneNumber: contact.phoneNumber,
            email: contact.email ?? '',
            jobTitle: contact.jobTitle,
            company: contact.company,
            website: contact.website,
            address: contact.address,
          );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScannedProfileScreen(profile: sharedProfile),
        ),
      ).then((_) => _loadAllContacts());
    }
  }

  void _openEditContact(UnifiedContactModel contact) {
    if (contact.source == ContactSourceType.businessCard &&
        contact.rawImportedContact != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EditImportedContactScreen(
            contact: contact.rawImportedContact!,
            contactService: _importedContactService,
          ),
        ),
      ).then((_) => _loadAllContacts());
    }
  }

  Future<void> _makePhoneCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _sendEmail(String email) async {
    final uri = Uri.parse('mailto:$email');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayedContacts = _filteredContacts;

    final businessCardCount =
        _allContacts.where((c) => c.source == ContactSourceType.businessCard).length;
    final qrCount =
        _allContacts.where((c) => c.source == ContactSourceType.qrScan).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Saved Contacts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Contacts',
            onPressed: _loadAllContacts,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('saved_contacts_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name, company, phone, email, memory...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                },
              ),
            ),

            // 2. Filter Tabs (All, Business Cards, QR Scans)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      key: const Key('filter_all_contacts'),
                      selected: _selectedFilter == ContactSourceType.all,
                      label: Text('All (${_allContacts.length})'),
                      onSelected: (_) {
                        setState(() {
                          _selectedFilter = ContactSourceType.all;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const Key('filter_business_cards'),
                      selected: _selectedFilter == ContactSourceType.businessCard,
                      avatar: const Icon(Icons.badge_rounded, size: 16),
                      label: Text('Business Cards ($businessCardCount)'),
                      onSelected: (_) {
                        setState(() {
                          _selectedFilter = ContactSourceType.businessCard;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      key: const Key('filter_qr_scans'),
                      selected: _selectedFilter == ContactSourceType.qrScan,
                      avatar: const Icon(Icons.qr_code_2_rounded, size: 16),
                      label: Text('QR Scans ($qrCount)'),
                      onSelected: (_) {
                        setState(() {
                          _selectedFilter = ContactSourceType.qrScan;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),

            // 3. Contact List Body
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadAllContacts,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline_rounded,
                                      size: 48, color: theme.colorScheme.error),
                                  const SizedBox(height: 12),
                                  Text(
                                    _errorMessage!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: theme.colorScheme.error),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _loadAllContacts,
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Try Again'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : displayedContacts.isEmpty
                            ? _buildEmptyState(theme)
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                itemCount: displayedContacts.length + 1,
                                itemBuilder: (ctx, index) {
                                  if (index == displayedContacts.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 24),
                                      child: MedindiaBrandingFooter(showDivider: true),
                                    );
                                  }
                                  final contact = displayedContacts[index];
                                  return _buildContactCard(context, theme, contact);
                                },
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final hasSearch = _searchQuery.trim().isNotEmpty;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearch ? Icons.search_off_rounded : Icons.contacts_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              hasSearch ? 'No Contacts Match Your Search' : 'No Saved Contacts Yet',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Try searching with different keywords such as name, company, phone, email, or memory notes.'
                  : 'Start expanding your professional network by scanning physical business cards or QR codes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BusinessCardScanScreen(),
                      ),
                    ).then((_) => _loadAllContacts());
                  },
                  icon: const Icon(Icons.badge_rounded),
                  label: const Text('Scan Business Card'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const QrScannerScreen(),
                      ),
                    ).then((_) => _loadAllContacts());
                  },
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Scan QR Code'),
                ),
              ],
            ),
            const SizedBox(height: 48),
            const MedindiaBrandingFooter(showDivider: true),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(
      BuildContext context, ThemeData theme, UnifiedContactModel contact) {
    final isBusinessCard = contact.source == ContactSourceType.businessCard;
    final sourceColor = isBusinessCard ? const Color(0xFF0D9488) : const Color(0xFF7C3AED);
    final sourceLabel = isBusinessCard ? 'Business Card' : 'QR Scan';
    final sourceIcon = isBusinessCard ? Icons.badge_rounded : Icons.qr_code_2_rounded;

    return Card(
      key: Key('unified_contact_${contact.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openContactDetails(contact),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Avatar, Name, Job/Company, Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar Circle
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: sourceColor.withValues(alpha: 0.15),
                    child: Text(
                      contact.fullName.isNotEmpty
                          ? contact.fullName.substring(0, 1).toUpperCase()
                          : '?',
                      style: TextStyle(
                        color: sourceColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Name & Role
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.fullName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (contact.jobTitle?.isNotEmpty == true ||
                            contact.company?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (contact.jobTitle?.isNotEmpty == true) contact.jobTitle,
                              if (contact.company?.isNotEmpty == true) contact.company,
                            ].join(' • '),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF0D9488),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Actions: Edit (if business card) and Delete
                  if (isBusinessCard)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Edit Contact',
                      onPressed: () => _openEditContact(contact),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        size: 20, color: theme.colorScheme.error),
                    tooltip: 'Delete Contact',
                    onPressed: () => _handleDeleteContact(contact),
                  ),
                ],
              ),

              // Contact Details: Phone, Email
              if (contact.phoneNumber?.isNotEmpty == true ||
                  contact.email?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                if (contact.phoneNumber?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.phone_outlined,
                            size: 15, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            contact.phoneNumber!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (contact.email?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.email_outlined,
                            size: 15, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            contact.email!,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],

              // Remember This Contact Memory Badge (Visual Reference Match!)
              if (contact.memory != null && contact.memory!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded,
                          size: 14, color: Color(0xFF1D4ED8)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Memory: ${contact.memory!}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D4ED8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              // Footer Badges & Quick Action Buttons
              Row(
                children: [
                  // Source Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: sourceColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(sourceIcon, size: 12, color: sourceColor),
                        const SizedBox(width: 4),
                        Text(
                          sourceLabel,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: sourceColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Quick Action: WhatsApp
                  if (contact.phoneNumber?.isNotEmpty == true)
                    IconButton.filledTonal(
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      tooltip: 'WhatsApp',
                      onPressed: () => _openWhatsApp(contact.phoneNumber!),
                    ),
                  const SizedBox(width: 6),

                  // Quick Action: Call
                  if (contact.phoneNumber?.isNotEmpty == true)
                    IconButton.filledTonal(
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.call_outlined, size: 16),
                      tooltip: 'Call',
                      onPressed: () => _makePhoneCall(contact.phoneNumber!),
                    ),
                  const SizedBox(width: 6),

                  // Quick Action: Email
                  if (contact.email?.isNotEmpty == true)
                    IconButton.filledTonal(
                      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.email_outlined, size: 16),
                      tooltip: 'Email',
                      onPressed: () => _sendEmail(contact.email!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

