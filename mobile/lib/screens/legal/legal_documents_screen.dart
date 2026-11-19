import 'package:flutter/material.dart';
import '../../services/legal_consent_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/medindia_branding_footer.dart';
import '../../config/legal_urls.dart';

class LegalDocumentsScreen extends StatefulWidget {
  final String? initialJurisdiction;
  final int initialTab; // 0: Terms, 1: Privacy, 2: Cookies

  const LegalDocumentsScreen({
    super.key,
    this.initialJurisdiction,
    this.initialTab = 0,
  });

  @override
  State<LegalDocumentsScreen> createState() => _LegalDocumentsScreenState();
}

class _LegalDocumentsScreenState extends State<LegalDocumentsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late String _selectedJurisdiction;
  LegalDocumentsData? _documents;
  bool _isLoading = true;

  final Map<String, String> _jurisdictions = {
    'IN': 'India (DPDP Act 2023)',
    'EU': 'European Union (GDPR)',
    'GB': 'United Kingdom (UK GDPR)',
    'US': 'United States (CCPA/CPRA)',
    'GLOBAL': 'Global / International',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 2),
    );
    _selectedJurisdiction = widget.initialJurisdiction ??
        LegalConsentService().detectDeviceJurisdiction();
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
    });

    final data =
        await LegalConsentService().fetchDocuments(_selectedJurisdiction);
    if (mounted) {
      setState(() {
        _documents = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal & Privacy Notices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: 'View Official Online Notice',
            onPressed: () {
              if (_tabController.index == 0) {
                LegalUrls.openTermsAndConditions();
              } else if (_tabController.index == 1) {
                LegalUrls.openPrivacyPolicy();
              } else {
                LegalUrls.openPrivacyCentre();
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Terms'),
            Tab(text: 'Privacy Policy'),
            Tab(text: 'Cookie Policy'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Jurisdiction Selector Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              child: Row(
                children: [
                  const Icon(Icons.gavel_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Jurisdiction:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedJurisdiction,
                        isExpanded: true,
                        items: _jurisdictions.entries.map((entry) {
                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null && val != _selectedJurisdiction) {
                            setState(() {
                              _selectedJurisdiction = val;
                            });
                            _loadDocuments();
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Document Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildDocumentViewer(
                          context,
                          theme,
                          title: 'Terms and Conditions',
                          version: _documents?.termsVersion ?? '2026.1',
                          content: _documents?.termsAndConditionsMarkdown ?? '',
                        ),
                        _buildDocumentViewer(
                          context,
                          theme,
                          title: 'Privacy Policy',
                          version: _documents?.privacyPolicyVersion ?? '2026.1',
                          content: _documents?.privacyPolicyMarkdown ?? '',
                          extraFooter: _buildGrievanceContact(theme),
                        ),
                        _buildDocumentViewer(
                          context,
                          theme,
                          title: 'Cookie & Local Storage Policy',
                          version: _documents?.cookiePolicyVersion ?? '2026.1',
                          content: _documents?.cookiePolicyMarkdown ?? '',
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentViewer(
    BuildContext context,
    ThemeData theme, {
    required String title,
    required String version,
    required String content,
    Widget? extraFooter,
  }) {
    return SingleChildScrollView(
      padding: AppSpacing.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Version: $version',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _selectedJurisdiction,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.5,
            ),
          ),
          if (extraFooter != null) ...[
            const SizedBox(height: 16),
            extraFooter,
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.launch_rounded, size: 16),
            label: Text('View official  online'),
            onPressed: () {
              if (title.contains('Terms')) {
                LegalUrls.openTermsAndConditions();
              } else if (title.contains('Privacy')) {
                LegalUrls.openPrivacyPolicy();
              } else {
                LegalUrls.openPrivacyCentre();
              }
            },
          ),
          const SizedBox(height: 24),
          const MedindiaBrandingFooter(showDivider: true),
        ],
      ),
    );
  }

  Widget _buildGrievanceContact(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Data Protection & Grievance Redressal',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _documents?.grievanceOfficer ?? 'Grievance Officer, Medindia4u.com',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Email: ${_documents?.contactEmail ?? 'privacy@medindia4u.com'}',
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

