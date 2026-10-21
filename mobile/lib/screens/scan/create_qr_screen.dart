import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../services/location/location_service.dart';
import '../../services/qr/qr_generator_service.dart';
import '../../theme/app_spacing.dart';
import 'widgets/map_location_picker.dart';

enum CreateQrType {
  website('Website', Icons.language_rounded),
  wifi('Wi-Fi', Icons.wifi_rounded),
  whatsapp('WhatsApp', Icons.chat_rounded),
  phone('Phone', Icons.phone_rounded),
  email('Email', Icons.email_rounded),
  sms('SMS', Icons.sms_rounded),
  contact('Contact', Icons.contact_page_rounded),
  location('Location', Icons.location_on_rounded),
  text('Plain Text', Icons.text_snippet_rounded);

  final String label;
  final IconData icon;
  const CreateQrType(this.label, this.icon);
}

enum LocationInputMode {
  mapPicker('Pick from Map', Icons.map_rounded),
  manual('Enter Manually', Icons.edit_location_alt_rounded);

  final String label;
  final IconData icon;
  const LocationInputMode(this.label, this.icon);
}

/// Universal QR Code Generator Screen.
class CreateQrScreen extends StatefulWidget {
  final LocationService? locationService;
  const CreateQrScreen({super.key, this.locationService});

  @override
  State<CreateQrScreen> createState() => CreateQrScreenState();
}

class CreateQrScreenState extends State<CreateQrScreen> {
  CreateQrType _selectedType = CreateQrType.website;
  LocationInputMode _locationMode = LocationInputMode.mapPicker;

  double? _selectedMapLat;
  double? _selectedMapLng;
  String? _selectedMapPlaceName;
  String? _selectedMapAddress;

  // Controllers for various types
  final _urlController = TextEditingController(text: 'https://');

  final _wifiSsidController = TextEditingController();
  final _wifiPassController = TextEditingController();
  String _wifiSecurity = 'WPA';
  bool _wifiHidden = false;
  bool _obscureWifiPass = true;

  final _waPhoneController = TextEditingController();
  final _waMessageController = TextEditingController();

  final _phoneController = TextEditingController();

  final _emailRecipientController = TextEditingController();
  final _emailSubjectController = TextEditingController();
  final _emailBodyController = TextEditingController();

  final _smsPhoneController = TextEditingController();
  final _smsMessageController = TextEditingController();

  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactCompanyController = TextEditingController();
  final _contactTitleController = TextEditingController();
  final _contactAddressController = TextEditingController();

  final _locLatController = TextEditingController();
  final _locLngController = TextEditingController();
  final _locLabelController = TextEditingController();

  final _textController = TextEditingController();

  String _generatedPayload = '';
  String? _errorMessage;

  String get generatedPayload => _generatedPayload;
  String? get errorMessage => _errorMessage;

  @override
  void initState() {
    super.initState();
    _recomputePayload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _wifiSsidController.dispose();
    _wifiPassController.dispose();
    _waPhoneController.dispose();
    _waMessageController.dispose();
    _phoneController.dispose();
    _emailRecipientController.dispose();
    _emailSubjectController.dispose();
    _emailBodyController.dispose();
    _smsPhoneController.dispose();
    _smsMessageController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _contactCompanyController.dispose();
    _contactTitleController.dispose();
    _contactAddressController.dispose();
    _locLatController.dispose();
    _locLngController.dispose();
    _locLabelController.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _recomputePayload() {
    setState(() {
      _errorMessage = null;
      try {
        switch (_selectedType) {
          case CreateQrType.website:
            final url = _urlController.text.trim();
            if (url.isNotEmpty && url != 'https://' && url != 'http://') {
              _generatedPayload = QrGeneratorService.buildWebsitePayload(url);
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.wifi:
            final ssid = _wifiSsidController.text.trim();
            if (ssid.isNotEmpty) {
              _generatedPayload = QrGeneratorService.buildWifiPayload(
                ssid: ssid,
                security: _wifiSecurity,
                password: _wifiPassController.text,
                isHidden: _wifiHidden,
              );
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.whatsapp:
            final phone = _waPhoneController.text.trim();
            if (phone.isNotEmpty) {
              _generatedPayload = QrGeneratorService.buildWhatsAppPayload(
                phone: phone,
                message: _waMessageController.text,
              );
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.phone:
            final phone = _phoneController.text.trim();
            if (phone.isNotEmpty) {
              _generatedPayload = QrGeneratorService.buildPhonePayload(phone);
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.email:
            final email = _emailRecipientController.text.trim();
            if (email.isNotEmpty) {
              _generatedPayload = QrGeneratorService.buildEmailPayload(
                email: email,
                subject: _emailSubjectController.text,
                body: _emailBodyController.text,
              );
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.sms:
            final phone = _smsPhoneController.text.trim();
            if (phone.isNotEmpty) {
              _generatedPayload = QrGeneratorService.buildSmsPayload(
                phone: phone,
                message: _smsMessageController.text,
              );
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.contact:
            final name = _contactNameController.text.trim();
            if (name.isNotEmpty) {
              final phones = _contactPhoneController.text.trim().isNotEmpty
                  ? [_contactPhoneController.text.trim()]
                  : <String>[];
              final emails = _contactEmailController.text.trim().isNotEmpty
                  ? [_contactEmailController.text.trim()]
                  : <String>[];
              _generatedPayload = QrGeneratorService.buildContactVCardPayload(
                name: name,
                phones: phones,
                emails: emails,
                company: _contactCompanyController.text,
                title: _contactTitleController.text,
                address: _contactAddressController.text,
              );
            } else {
              _generatedPayload = '';
            }
            break;

          case CreateQrType.location:
            if (_locationMode == LocationInputMode.mapPicker) {
              if (_selectedMapLat != null && _selectedMapLng != null) {
                _generatedPayload = QrGeneratorService.buildLocationPayload(
                  latitude: _selectedMapLat!,
                  longitude: _selectedMapLng!,
                  label: _locLabelController.text,
                );
              } else {
                _generatedPayload = '';
              }
            } else {
              final lat = double.tryParse(_locLatController.text.trim());
              final lng = double.tryParse(_locLngController.text.trim());
              if (lat != null && lng != null) {
                _generatedPayload = QrGeneratorService.buildLocationPayload(
                  latitude: lat,
                  longitude: lng,
                  label: _locLabelController.text,
                );
              } else {
                _generatedPayload = '';
              }
            }
            break;

          case CreateQrType.text:
            _generatedPayload = _textController.text.trim();
            break;
        }
      } on ArgumentError catch (e) {
        _errorMessage = e.message?.toString() ?? e.toString();
        _generatedPayload = '';
      } catch (e) {
        _errorMessage = e.toString();
        _generatedPayload = '';
      }
    });
  }

  void _copyPayload() {
    if (_generatedPayload.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _generatedPayload));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR payload copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create QR Code'),
        actions: [
          if (_generatedPayload.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded),
              tooltip: 'Copy Payload',
              onPressed: _copyPayload,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Type Selector Carousel / Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: CreateQrType.values.map((type) {
                    final isSelected = type == _selectedType;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        key: Key('create_type_${type.name}'),
                        avatar: Icon(
                          type.icon,
                          size: 18,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        label: Text(type.label),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _selectedType = type;
                              _recomputePayload();
                            });
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Inputs Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.radiusLg,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: AppSpacing.cardPadding,
                  child: _buildFormForType(theme),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // QR Code Live Preview Card
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: AppSpacing.radiusLg,
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Text(
                        'QR Code Preview',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_errorMessage != null)
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: theme.colorScheme.error),
                        )
                      else if (_generatedPayload.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: AppSpacing.radiusMd,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: _generatedPayload,
                            version: QrVersions.auto,
                            size: 190.0,
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
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Standard ${_selectedType.label} QR',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          key: const Key('copy_created_qr_button'),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy QR Text / Payload'),
                          onPressed: _copyPayload,
                        ),
                      ] else ...[
                        Container(
                          height: 190,
                          width: 190,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: AppSpacing.radiusMd,
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_2_rounded,
                                size: 48,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter details above\nto generate QR',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormForType(ThemeData theme) {
    switch (_selectedType) {
      case CreateQrType.website:
        return TextField(
          key: const Key('input_website_url'),
          controller: _urlController,
          decoration: const InputDecoration(
            labelText: 'Website URL',
            hintText: 'https://example.com',
            prefixIcon: Icon(Icons.link_rounded),
          ),
          keyboardType: TextInputType.url,
          onChanged: (_) => _recomputePayload(),
        );

      case CreateQrType.wifi:
        return Column(
          children: [
            TextField(
              key: const Key('input_wifi_ssid'),
              controller: _wifiSsidController,
              decoration: const InputDecoration(
                labelText: 'Network Name (SSID)',
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('select_wifi_security'),
              initialValue: _wifiSecurity,
              decoration: const InputDecoration(
                labelText: 'Security Type',
                prefixIcon: Icon(Icons.security_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'WPA', child: Text('WPA / WPA2 / WPA3')),
                DropdownMenuItem(value: 'WEP', child: Text('WEP')),
                DropdownMenuItem(value: 'nopass', child: Text('None (Open Network)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _wifiSecurity = val;
                    _recomputePayload();
                  });
                }
              },
            ),
            if (_wifiSecurity != 'nopass') ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('input_wifi_password'),
                controller: _wifiPassController,
                obscureText: _obscureWifiPass,
                decoration: InputDecoration(
                  labelText: 'Wi-Fi Password',
                  prefixIcon: const Icon(Icons.password_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureWifiPass
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded),
                    onPressed: () =>
                        setState(() => _obscureWifiPass = !_obscureWifiPass),
                  ),
                ),
                onChanged: (_) => _recomputePayload(),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hidden Network'),
              value: _wifiHidden,
              onChanged: (val) {
                setState(() {
                  _wifiHidden = val;
                  _recomputePayload();
                });
              },
            ),
          ],
        );

      case CreateQrType.whatsapp:
        return Column(
          children: [
            TextField(
              key: const Key('input_whatsapp_phone'),
              controller: _waPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number (with Country Code)',
                hintText: 'Enter phone number with country code',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
              keyboardType: TextInputType.phone,
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('input_whatsapp_message'),
              controller: _waMessageController,
              decoration: const InputDecoration(
                labelText: 'Optional Message',
                hintText: 'Hello! Let\'s connect.',
                prefixIcon: Icon(Icons.message_rounded),
              ),
              maxLines: 2,
              onChanged: (_) => _recomputePayload(),
            ),
          ],
        );

      case CreateQrType.phone:
        return TextField(
          key: const Key('input_phone_number'),
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            hintText: '+1 555-0199 or +91 98765 43210',
            prefixIcon: Icon(Icons.call_rounded),
          ),
          keyboardType: TextInputType.phone,
          onChanged: (_) => _recomputePayload(),
        );

      case CreateQrType.email:
        return Column(
          children: [
            TextField(
              key: const Key('input_email_recipient'),
              controller: _emailRecipientController,
              decoration: const InputDecoration(
                labelText: 'Recipient Email',
                hintText: 'user@example.com',
                prefixIcon: Icon(Icons.email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailSubjectController,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.subject_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _emailBodyController,
              decoration: const InputDecoration(
                labelText: 'Body Text',
                prefixIcon: Icon(Icons.notes_rounded),
              ),
              maxLines: 2,
              onChanged: (_) => _recomputePayload(),
            ),
          ],
        );

      case CreateQrType.sms:
        return Column(
          children: [
            TextField(
              key: const Key('input_sms_phone'),
              controller: _smsPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '+91 98765 43210',
                prefixIcon: Icon(Icons.sms_rounded),
              ),
              keyboardType: TextInputType.phone,
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('input_sms_message'),
              controller: _smsMessageController,
              decoration: const InputDecoration(
                labelText: 'Message',
                prefixIcon: Icon(Icons.message_rounded),
              ),
              maxLines: 2,
              onChanged: (_) => _recomputePayload(),
            ),
          ],
        );

      case CreateQrType.contact:
        return Column(
          children: [
            TextField(
              key: const Key('input_contact_name'),
              controller: _contactNameController,
              decoration: const InputDecoration(
                labelText: 'Full Name *',
                prefixIcon: Icon(Icons.person_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('input_contact_phone'),
              controller: _contactPhoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
              keyboardType: TextInputType.phone,
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('input_contact_email'),
              controller: _contactEmailController,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _contactCompanyController,
              decoration: const InputDecoration(
                labelText: 'Company / Organization',
                prefixIcon: Icon(Icons.business_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _contactTitleController,
              decoration: const InputDecoration(
                labelText: 'Job Title',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _contactAddressController,
              decoration: const InputDecoration(
                labelText: 'Address',
                prefixIcon: Icon(Icons.location_on_rounded),
              ),
              onChanged: (_) => _recomputePayload(),
            ),
          ],
        );

      case CreateQrType.location:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SegmentedButton<LocationInputMode>(
                key: const Key('location_mode_segmented_button'),
                segments: LocationInputMode.values.map((mode) {
                  return ButtonSegment<LocationInputMode>(
                    value: mode,
                    label: Text(mode.label),
                    icon: Icon(mode.icon),
                  );
                }).toList(),
                selected: {_locationMode},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _locationMode = newSelection.first;
                    if (_locationMode == LocationInputMode.manual) {
                      if (_selectedMapLat != null) {
                        _locLatController.text =
                            _selectedMapLat!.toStringAsFixed(6);
                      }
                      if (_selectedMapLng != null) {
                        _locLngController.text =
                            _selectedMapLng!.toStringAsFixed(6);
                      }
                    } else {
                      final lat =
                          double.tryParse(_locLatController.text.trim());
                      final lng =
                          double.tryParse(_locLngController.text.trim());
                      if (lat != null &&
                          lng != null &&
                          lat >= -90.0 &&
                          lat <= 90.0 &&
                          lng >= -180.0 &&
                          lng <= 180.0) {
                        _selectedMapLat = lat;
                        _selectedMapLng = lng;
                      }
                    }
                    _recomputePayload();
                  });
                },
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_locationMode == LocationInputMode.mapPicker) ...[
              MapLocationPicker(
                locationService: widget.locationService,
                initialLatitude: _selectedMapLat,
                initialLongitude: _selectedMapLng,
                initialPlaceName: _selectedMapPlaceName,
                initialAddress: _selectedMapAddress,
                onLocationSelected: (result) {
                  setState(() {
                    _selectedMapLat = result.latitude;
                    _selectedMapLng = result.longitude;
                    _selectedMapPlaceName = result.placeName;
                    _selectedMapAddress = result.formattedAddress;
                    _locLatController.text =
                        result.latitude.toStringAsFixed(6);
                    _locLngController.text =
                        result.longitude.toStringAsFixed(6);
                    if (_locLabelController.text.trim().isEmpty ||
                        _locLabelController.text == _selectedMapPlaceName) {
                      _locLabelController.text = result.placeName;
                    }
                    _recomputePayload();
                  });
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('input_location_label'),
                controller: _locLabelController,
                decoration: const InputDecoration(
                  labelText: 'Optional Label / Place Name',
                  hintText: 'e.g. Meeting Point, Office, Home',
                  prefixIcon: Icon(Icons.label_rounded),
                ),
                onChanged: (_) => _recomputePayload(),
              ),
            ] else ...[
              TextField(
                key: const Key('input_location_lat'),
                controller: _locLatController,
                decoration: const InputDecoration(
                  labelText: 'Latitude (-90 to +90)',
                  hintText: 'e.g. 37.7749',
                  prefixIcon: Icon(Icons.my_location_rounded),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => _recomputePayload(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('input_location_lng'),
                controller: _locLngController,
                decoration: const InputDecoration(
                  labelText: 'Longitude (-180 to +180)',
                  hintText: 'e.g. -122.4194',
                  prefixIcon: Icon(Icons.location_searching_rounded),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                onChanged: (_) => _recomputePayload(),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('input_location_label'),
                controller: _locLabelController,
                decoration: const InputDecoration(
                  labelText: 'Optional Label / Place Name',
                  hintText: 'e.g. Meeting Point, Office, Home',
                  prefixIcon: Icon(Icons.label_rounded),
                ),
                onChanged: (_) => _recomputePayload(),
              ),
            ],
          ],
        );

      case CreateQrType.text:
        return TextField(
          key: const Key('input_plain_text'),
          controller: _textController,
          decoration: const InputDecoration(
            labelText: 'Text Content',
            hintText: 'Type or paste anything...',
            prefixIcon: Icon(Icons.text_fields_rounded),
          ),
          maxLines: 4,
          onChanged: (_) => _recomputePayload(),
        );
    }
  }
}
