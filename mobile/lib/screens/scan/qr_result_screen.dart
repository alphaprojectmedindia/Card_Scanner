import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/business_card_email.dart';
import '../../models/business_card_phone.dart';
import '../../models/qr/qr_content_type.dart';
import '../../models/qr/qr_scan_models.dart';
import '../../services/contact_communication_service.dart';
import '../../services/contact_service.dart';
import '../../theme/app_spacing.dart';

/// Polished Material 3 display screen for scanned Universal QR code results.
///
/// Strictly enforces security: NEVER automatically launches links, calls,
/// SMS, or external actions. Requires explicit user action.
class QrResultScreen extends StatefulWidget {
  final QrScanResult scanResult;
  final IContactService? contactService;
  final IContactCommunicationService? communicationService;

  const QrResultScreen({
    super.key,
    required this.scanResult,
    this.contactService,
    this.communicationService,
  });

  @override
  State<QrResultScreen> createState() => _QrResultScreenState();
}

class _QrResultScreenState extends State<QrResultScreen> {
  late final IContactService _contactService;
  late final IContactCommunicationService _communicationService;

  bool _isPasswordVisible = false;
  bool _isSavingContact = false;

  @override
  void initState() {
    super.initState();
    _contactService = widget.contactService ?? ContactService();
    _communicationService = widget.communicationService ?? const ContactCommunicationService();
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchExternalUrl(String urlString) async {
    try {
      final uri = Uri.tryParse(urlString);
      if (uri == null) {
        _showErrorSnackBar('Malformed URL cannot be opened.');
        return;
      }
      final canLaunch = await canLaunchUrl(uri);
      if (canLaunch) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar('No application available to open this link.');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to open link: $e');
    }
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleSaveContact(ContactQrData contact) async {
    if (_isSavingContact) return;
    setState(() => _isSavingContact = true);

    try {
      final phones = contact.phones.map((p) => BusinessCardPhone(number: p)).toList();
      final emails = contact.emails.map((e) => BusinessCardEmail(email: e)).toList();

      final result = await _contactService.saveBusinessCardToPhone(
        fullName: contact.fullName,
        company: contact.organization,
        jobTitle: contact.title,
        website: contact.website,
        address: contact.address,
        phones: phones,
        emails: emails,
      );

      if (!mounted) return;
      if (result.isSuccess) {
        _showSuccessSnackBar(result.message);
      } else {
        _showErrorSnackBar(result.message);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save contact: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingContact = false);
      }
    }
  }

  Future<void> _handleSavePhoneContact(String phone) async {
    if (_isSavingContact) return;
    setState(() => _isSavingContact = true);

    try {
      final result = await _contactService.saveBusinessCardToPhone(
        fullName: 'Contact ($phone)',
        company: null,
        jobTitle: null,
        website: null,
        address: null,
        phones: [BusinessCardPhone(number: phone)],
        emails: [],
      );

      if (!mounted) return;
      if (result.isSuccess) {
        _showSuccessSnackBar(result.message);
      } else {
        _showErrorSnackBar(result.message);
      }
    } catch (e) {
      _showErrorSnackBar('Failed to save contact: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingContact = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.scanResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanned QR Code'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy Raw Content',
            onPressed: () => _copyToClipboard(result.rawValue, 'Raw QR content'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type Banner Card
              _buildTypeHeader(theme, result),
              const SizedBox(height: AppSpacing.lg),

              // Content Specific Card
              _buildContentCard(theme, result),
              const SizedBox(height: AppSpacing.xxl),

              // Scan Again Button
              OutlinedButton.icon(
                key: const Key('qr_scan_again_button'),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan Another Code'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: AppSpacing.radiusMd),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeHeader(ThemeData theme, QrScanResult result) {
    final IconData icon;
    final String title;
    final Color color;

    switch (result.type) {
      case QrContentType.digitalShare:
        icon = Icons.badge_rounded;
        title = 'Digital Share Profile';
        color = theme.colorScheme.primary;
        break;
      case QrContentType.url:
        icon = Icons.language_rounded;
        title = 'Website Link';
        color = Colors.teal;
        break;
      case QrContentType.whatsapp:
        final waData = result.dataAs<WhatsAppQrData>();
        icon = Icons.chat_rounded;
        title = waData.hasPhone ? 'WhatsApp Chat' : 'WhatsApp';
        color = Colors.green;
        break;
      case QrContentType.wifi:
        icon = Icons.wifi_rounded;
        title = 'Wi-Fi Network';
        color = Colors.indigo;
        break;
      case QrContentType.geo:
        icon = Icons.location_on_rounded;
        title = 'Location';
        color = Colors.deepOrange;
        break;
      case QrContentType.phone:
        icon = Icons.phone_rounded;
        title = 'Phone Number';
        color = Colors.blue;
        break;
      case QrContentType.email:
        icon = Icons.email_rounded;
        title = 'Email Message';
        color = Colors.purple;
        break;
      case QrContentType.sms:
        icon = Icons.sms_rounded;
        title = 'SMS Message';
        color = Colors.amber.shade800;
        break;
      case QrContentType.vcard:
      case QrContentType.mecard:
        icon = Icons.contact_page_rounded;
        title = 'Contact Card';
        color = Colors.cyan.shade800;
        break;
      case QrContentType.event:
        icon = Icons.event_rounded;
        title = 'Calendar Event';
        color = Colors.deepPurple;
        break;
      case QrContentType.appLink:
        icon = Icons.open_in_new_rounded;
        title = 'Application Link';
        color = Colors.brown;
        break;
      case QrContentType.text:
        icon = Icons.text_snippet_rounded;
        title = 'Plain Text';
        color = theme.colorScheme.secondary;
        break;
      case QrContentType.unknown:
        icon = Icons.help_outline_rounded;
        title = 'QR Content';
        color = theme.colorScheme.outline;
        break;
    }

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.radiusLg,
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: AppSpacing.radiusMd,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Scanned successfully',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentCard(ThemeData theme, QrScanResult result) {
    switch (result.type) {
      case QrContentType.digitalShare:
        final data = result.dataAs<DigitalShareQrData>();
        return _buildDigitalShareCard(theme, data);

      case QrContentType.url:
        final data = result.dataAs<UrlQrData>();
        return _buildUrlCard(theme, data);

      case QrContentType.whatsapp:
        final data = result.dataAs<WhatsAppQrData>();
        return _buildWhatsAppCard(theme, data);

      case QrContentType.wifi:
        final data = result.dataAs<WifiQrData>();
        return _buildWifiCard(theme, data);

      case QrContentType.geo:
        final data = result.dataAs<GeoQrData>();
        return _buildGeoCard(theme, data);

      case QrContentType.phone:
        final data = result.dataAs<PhoneQrData>();
        return _buildPhoneCard(theme, data);

      case QrContentType.email:
        final data = result.dataAs<EmailQrData>();
        return _buildEmailCard(theme, data);

      case QrContentType.sms:
        final data = result.dataAs<SmsQrData>();
        return _buildSmsCard(theme, data);

      case QrContentType.vcard:
      case QrContentType.mecard:
        final data = result.dataAs<ContactQrData>();
        return _buildContactCard(theme, data);

      case QrContentType.event:
        final data = result.dataAs<CalendarEventQrData>();
        return _buildEventCard(theme, data);

      case QrContentType.appLink:
        final data = result.dataAs<AppLinkQrData>();
        return _buildAppLinkCard(theme, data);

      case QrContentType.text:
        final data = result.dataAs<TextQrData>();
        return _buildTextCard(theme, data.text);

      case QrContentType.unknown:
        final data = result.dataAs<UnknownQrData>();
        return _buildUnknownCard(theme, data);
    }
  }

  // 1. Digital Share
  Widget _buildDigitalShareCard(ThemeData theme, DigitalShareQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        _buildInfoRow(theme, 'Share ID', data.shareId),
        const SizedBox(height: AppSpacing.sm),
        _buildInfoRow(theme, 'Canonical URL', data.canonicalUrl),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('open_digital_share_button'),
          icon: const Icon(Icons.person_search_rounded),
          label: const Text('View Digital Card Profile'),
          onPressed: () => _copyToClipboard(data.canonicalUrl, 'Profile URL'),
        ),
      ],
    );
  }

  // 2. Website URL
  Widget _buildUrlCard(ThemeData theme, UrlQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Row(
          children: [
            Icon(
              data.isSecure ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
              size: 18,
              color: data.isSecure ? Colors.green : Colors.amber.shade800,
            ),
            const SizedBox(width: 6),
            Text(
              data.isSecure ? 'Secure Connection (HTTPS)' : 'Standard HTTP (Unencrypted)',
              style: theme.textTheme.labelMedium?.copyWith(
                color: data.isSecure ? Colors.green : Colors.amber.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          data.displayHost,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          data.url,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('open_website_button'),
          icon: const Icon(Icons.open_in_browser_rounded),
          label: const Text('Open Website'),
          onPressed: () => _launchExternalUrl(data.url),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy Link'),
                onPressed: () => _copyToClipboard(data.url, 'Website link'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 3. WhatsApp
  Widget _buildWhatsAppCard(ThemeData theme, WhatsAppQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        if (data.hasPhone) ...[
          _buildInfoRow(theme, 'Number', data.phone),
        ],
        if (data.hasMessage) ...[
          if (data.hasPhone) const SizedBox(height: AppSpacing.md),
          _buildInfoRow(theme, 'Message', data.message),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('open_whatsapp_button'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
          icon: const Icon(Icons.chat_rounded, color: Colors.white),
          label: const Text('Open WhatsApp', style: TextStyle(color: Colors.white)),
          onPressed: () async {
            final ok = await _communicationService.openWhatsApp(
              phone: data.phone,
              message: data.message,
              linkUrl: data.linkUrl,
            );
            if (!ok) {
              _showErrorSnackBar('Could not launch WhatsApp.');
            }
          },
        ),
        if (data.hasPhone) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('copy_whatsapp_number_button'),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Number'),
            onPressed: () => _copyToClipboard(data.phone, 'Phone number'),
          ),
        ],
        if (data.hasMessage) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: const Key('copy_whatsapp_message_button'),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Message'),
            onPressed: () => _copyToClipboard(data.message, 'Message'),
          ),
        ],
      ],
    );
  }

  // 4. Wi-Fi
  Widget _buildWifiCard(ThemeData theme, WifiQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        _buildInfoRow(theme, 'Network Name (SSID)', data.ssid),
        const SizedBox(height: AppSpacing.md),
        _buildInfoRow(theme, 'Security', data.security),
        if (data.isHidden) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Hidden Network',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Password',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppSpacing.radiusSm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isPasswordVisible
                      ? (data.password.isEmpty ? '(No password required)' : data.password)
                      : (data.password.isEmpty ? '(Open Network)' : '•' * data.password.length),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (data.password.isNotEmpty)
                IconButton(
                  key: const Key('toggle_wifi_password_button'),
                  icon: Icon(
                    _isPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    size: 20,
                  ),
                  tooltip: _isPasswordVisible ? 'Hide Password' : 'Show Password',
                  onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (data.password.isNotEmpty) ...[
          FilledButton.icon(
            key: const Key('copy_wifi_password_button'),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Password'),
            onPressed: () => _copyToClipboard(data.password, 'Wi-Fi password'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.info_outline_rounded),
          label: const Text('Copy Network Details'),
          onPressed: () => _copyToClipboard(
            'Network: ${data.ssid}\nSecurity: ${data.security}',
            'Network details',
          ),
        ),
      ],
    );
  }

  // 5. Geo Location
  Widget _buildGeoCard(ThemeData theme, GeoQrData data) {
    final hasCoords = data.latitude != null && data.longitude != null;
    return _buildCardWrapper(
      theme,
      children: [
        if (hasCoords) ...[
          _buildInfoRow(theme, 'Latitude', data.latitude!.toStringAsFixed(6)),
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Longitude', data.longitude!.toStringAsFixed(6)),
        ],
        if (data.query != null && data.query!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Query / Label', data.query!),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('open_maps_button'),
          icon: const Icon(Icons.map_rounded),
          label: const Text('Open in Maps'),
          onPressed: () => _launchExternalUrl(data.rawUri),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (hasCoords)
          OutlinedButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Coordinates'),
            onPressed: () => _copyToClipboard(
              '${data.latitude}, ${data.longitude}',
              'Coordinates',
            ),
          ),
      ],
    );
  }

  // 6. Phone
  Widget _buildPhoneCard(ThemeData theme, PhoneQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Text(
          data.phoneNumber,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('call_phone_button'),
          icon: const Icon(Icons.call_rounded),
          label: const Text('Call Number'),
          onPressed: () => _launchExternalUrl('tel:${data.phoneNumber}'),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          key: const Key('save_phone_contact_button'),
          icon: _isSavingContact
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_rounded),
          label: const Text('Save to Contacts'),
          onPressed: _isSavingContact ? null : () => _handleSavePhoneContact(data.phoneNumber),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Phone Number'),
          onPressed: () => _copyToClipboard(data.phoneNumber, 'Phone number'),
        ),
      ],
    );
  }

  // 7. Email
  Widget _buildEmailCard(ThemeData theme, EmailQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        _buildInfoRow(theme, 'Recipient', data.email),
        if (data.subject.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Subject', data.subject),
        ],
        if (data.body.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Body', data.body),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('send_email_button'),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Send Email'),
          onPressed: () => _communicationService.openEmail(
            email: data.email,
            subject: data.subject,
            body: data.body,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Email Address'),
          onPressed: () => _copyToClipboard(data.email, 'Email address'),
        ),
      ],
    );
  }

  // 8. SMS
  Widget _buildSmsCard(ThemeData theme, SmsQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        _buildInfoRow(theme, 'Send SMS To', data.phoneNumber),
        if (data.message.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Message', data.message),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('open_sms_button'),
          icon: const Icon(Icons.sms_rounded),
          label: const Text('Open in Messages'),
          onPressed: () {
            final encoded = Uri.encodeComponent(data.message);
            _launchExternalUrl('sms:${data.phoneNumber}?body=$encoded');
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Phone Number'),
          onPressed: () => _copyToClipboard(data.phoneNumber, 'Phone number'),
        ),
      ],
    );
  }

  // 9. Contact Card (vCard & MECARD)
  Widget _buildContactCard(ThemeData theme, ContactQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Text(
          data.fullName,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (data.title != null && data.title!.isNotEmpty)
          Text(data.title!, style: theme.textTheme.bodyMedium),
        if (data.organization != null && data.organization!.isNotEmpty)
          Text(data.organization!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const Divider(height: 24),
        if (data.phones.isNotEmpty) ...[
          Text('Phone Numbers', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...data.phones.map((p) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_outlined, size: 20),
                title: Text(p),
                trailing: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _copyToClipboard(p, 'Phone'),
                ),
              )),
          const SizedBox(height: 8),
        ],
        if (data.emails.isNotEmpty) ...[
          Text('Email Addresses', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...data.emails.map((e) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.email_outlined, size: 20),
                title: Text(e),
                trailing: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () => _copyToClipboard(e, 'Email'),
                ),
              )),
          const SizedBox(height: 8),
        ],
        if (data.website != null && data.website!.isNotEmpty)
          _buildInfoRow(theme, 'Website', data.website!),
        if (data.address != null && data.address!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Address', data.address!),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('save_vcard_contact_button'),
          icon: _isSavingContact
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_add_rounded),
          label: const Text('Save Contact to Phone'),
          onPressed: _isSavingContact ? null : () => _handleSaveContact(data),
        ),
      ],
    );
  }

  // 10. Calendar Event
  Widget _buildEventCard(ThemeData theme, CalendarEventQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Text(
          data.summary,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (data.dtStart != null)
          _buildInfoRow(theme, 'Starts', data.dtStart.toString())
        else if (data.rawDtStart != null)
          _buildInfoRow(theme, 'Starts', data.rawDtStart!),
        if (data.dtEnd != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildInfoRow(theme, 'Ends', data.dtEnd.toString()),
        ],
        if (data.location != null && data.location!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Location', data.location!),
        ],
        if (data.description != null && data.description!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _buildInfoRow(theme, 'Description', data.description!),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('copy_event_details_button'),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Event Details'),
          onPressed: () {
            final details = 'Event: ${data.summary}\n'
                'Starts: ${data.dtStart ?? data.rawDtStart ?? 'N/A'}\n'
                'Location: ${data.location ?? 'N/A'}\n'
                'Description: ${data.description ?? ''}';
            _copyToClipboard(details, 'Event details');
          },
        ),
      ],
    );
  }

  // 11. App Link
  Widget _buildAppLinkCard(ThemeData theme, AppLinkQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Row(
          children: [
            Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.error),
            const SizedBox(width: 6),
            Text(
              'Custom App Scheme: ${data.scheme}',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'For security, arbitrary application links are not automatically executed.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableText(
          data.uri,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy URI'),
          onPressed: () => _copyToClipboard(data.uri, 'App URI'),
        ),
      ],
    );
  }

  // 12. Plain Text
  Widget _buildTextCard(ThemeData theme, String text) {
    return _buildCardWrapper(
      theme,
      children: [
        Container(
          width: double.infinity,
          constraints: const Duration(milliseconds: 300) == Duration.zero
              ? null
              : const BoxConstraints(maxHeight: 250),
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppSpacing.radiusMd,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${text.length} characters • ${text.split('\n').length} lines',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          key: const Key('copy_plain_text_button'),
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Text'),
          onPressed: () => _copyToClipboard(text, 'Text'),
        ),
      ],
    );
  }

  // 13. Unknown
  Widget _buildUnknownCard(ThemeData theme, UnknownQrData data) {
    return _buildCardWrapper(
      theme,
      children: [
        Text(
          data.message,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Raw Content:',
          style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AppSpacing.radiusMd,
          ),
          child: SelectableText(
            data.rawContent,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy Content'),
          onPressed: () => _copyToClipboard(data.rawContent, 'Content'),
        ),
      ],
    );
  }

  Widget _buildCardWrapper(ThemeData theme, {required List<Widget> children}) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.radiusLg,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
