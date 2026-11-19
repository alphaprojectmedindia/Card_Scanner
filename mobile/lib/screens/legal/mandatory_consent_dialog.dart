import 'package:flutter/material.dart';
import '../../services/legal_consent_service.dart';
import 'legal_documents_screen.dart';
import '../../config/legal_urls.dart';

class MandatoryConsentDialog extends StatefulWidget {
  final String? initialJurisdiction;
  final VoidCallback onConsentGranted;

  const MandatoryConsentDialog({
    super.key,
    this.initialJurisdiction,
    required this.onConsentGranted,
  });

  static Future<bool?> show(
    BuildContext context, {
    String? initialJurisdiction,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => MandatoryConsentDialog(
        initialJurisdiction: initialJurisdiction,
        onConsentGranted: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  State<MandatoryConsentDialog> createState() => _MandatoryConsentDialogState();
}

class _MandatoryConsentDialogState extends State<MandatoryConsentDialog> {
  late String _jurisdiction;
  bool _termsAccepted = false; // NEVER automatically checked
  bool _analyticsAccepted = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _jurisdiction = widget.initialJurisdiction ??
        LegalConsentService().detectDeviceJurisdiction();
  }

  Future<void> _handleAccept() async {
    if (!_termsAccepted) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      await LegalConsentService().recordConsent(
        jurisdiction: _jurisdiction,
        essentialAccepted: true,
        analyticsAccepted: _analyticsAccepted,
      );
      if (mounted) {
        widget.onConsentGranted();
      }
    } catch (_) {
      if (mounted) {
        widget.onConsentGranted();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _openLegalDocuments(int tab) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentsScreen(
          initialJurisdiction: _jurisdiction,
          initialTab: tab,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.policy_rounded,
                      color: theme.colorScheme.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms & Privacy Update',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Powered by Medindia4u.com • v2026.1',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Please review and accept our updated Terms of Service and Privacy Policy before continuing. Digital Share protects your personal data in accordance with applicable data protection legislation.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),

              // Document Links
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.description_outlined, size: 16),
                    label: const Text('Terms of Service'),
                    onPressed: () async {
                      final launched = await LegalUrls.openTermsAndConditions();
                      if (!launched && mounted) _openLegalDocuments(0);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.privacy_tip_outlined, size: 16),
                    label: const Text('Privacy Policy'),
                    onPressed: () async {
                      final launched = await LegalUrls.openPrivacyPolicy();
                      if (!launched && mounted) _openLegalDocuments(1);
                    },
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.cookie_outlined, size: 16),
                    label: const Text('Cookie Policy'),
                    onPressed: () => _openLegalDocuments(2),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Mandatory Consent Checkbox
              CheckboxListTile(
                key: const Key('mandatory_consent_checkbox'),
                value: _termsAccepted,
                onChanged: (val) {
                  setState(() {
                    _termsAccepted = val ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'I have read and agree to the Terms and Conditions and Privacy Policy for jurisdiction ($_jurisdiction).',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),

              // Optional Analytics Checkbox
              CheckboxListTile(
                key: const Key('optional_analytics_checkbox'),
                value: _analyticsAccepted,
                onChanged: (val) {
                  setState(() {
                    _analyticsAccepted = val ?? false;
                  });
                },
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Allow optional anonymous usage analytics to help improve Digital Share.',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: const Text(
                  'Declining analytics will not affect any application functionality.',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(height: 20),

              // Submit Action
              FilledButton(
                key: const Key('confirm_consent_button'),
                onPressed: (_termsAccepted && !_isSubmitting) ? _handleAccept : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Accept and Continue',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

