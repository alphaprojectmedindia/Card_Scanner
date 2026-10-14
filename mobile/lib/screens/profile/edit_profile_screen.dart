import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/api_config.dart';
import '../../models/update_profile_request.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/profile_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/primary_button.dart';

class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;
  final ProfileService? profileService;
  final ImagePicker? imagePicker;

  const EditProfileScreen({
    super.key,
    required this.profile,
    this.profileService,
    this.imagePicker,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ProfileService _profileService;
  late final ImagePicker _imagePicker;

  late UserProfile _currentProfile;
  File? _localImageFile;
  bool _isUploadingPhoto = false;

  late TextEditingController _fullNameController;
  late TextEditingController _phoneNumberController;
  late TextEditingController _emailController;
  late TextEditingController _jobTitleController;
  late TextEditingController _companyController;
  late TextEditingController _websiteController;
  late TextEditingController _addressController;
  late TextEditingController _bioController;

  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _profileService = widget.profileService ?? ProfileService();
    _imagePicker = widget.imagePicker ?? ImagePicker();

    _currentProfile = widget.profile;
    _fullNameController = TextEditingController(text: widget.profile.fullName ?? '');
    _phoneNumberController = TextEditingController(text: widget.profile.phoneNumber ?? '');
    _emailController = TextEditingController(text: widget.profile.email);
    _jobTitleController = TextEditingController(text: widget.profile.jobTitle ?? '');
    _companyController = TextEditingController(text: widget.profile.company ?? '');
    _websiteController = TextEditingController(text: widget.profile.website ?? '');
    _addressController = TextEditingController(text: widget.profile.address ?? '');
    _bioController = TextEditingController(text: widget.profile.bio ?? '');
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneNumberController.dispose();
    _emailController.dispose();
    _jobTitleController.dispose();
    _companyController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _showPhotoOptionsSheet() {
    final theme = Theme.of(context);

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  'Profile Photo',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.of(bottomSheetContext).pop();
                    _pickAndUploadImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Choose from Gallery'),
                  onTap: () {
                    Navigator.of(bottomSheetContext).pop();
                    _pickAndUploadImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.of(bottomSheetContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // Selection cancelled by user gracefully
        return;
      }

      final file = File(pickedFile.path);
      final fileSize = await file.length();
      const maxPhotoSizeBytes = 5 * 1024 * 1024; // 5 MB

      if (fileSize > maxPhotoSizeBytes) {
        setState(() {
          _errorMessage = 'Selected image exceeds the 5 MB limit. Please select a smaller photo.';
        });
        return;
      }

      // Determine content type safely based on extension
      final extension = pickedFile.path.split('.').last.toLowerCase();
      String contentType = 'image/jpeg';
      if (extension == 'png') {
        contentType = 'image/png';
      } else if (extension == 'webp') {
        contentType = 'image/webp';
      } else if (extension == 'gif') {
        contentType = 'image/gif';
      }

      // Show local preview immediately before upload starts
      setState(() {
        _localImageFile = file;
        _isUploadingPhoto = true;
        _errorMessage = '';
      });

      final updatedProfile = await _profileService.uploadProfilePhoto(
        filePath: file.path,
        filename: pickedFile.name,
        contentType: contentType,
      );

      if (!mounted) return;

      setState(() {
        _currentProfile = updatedProfile;
        _isUploadingPhoto = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo uploaded successfully!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _localImageFile = null;
          _isUploadingPhoto = false;
          _errorMessage = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _localImageFile = null;
          _isUploadingPhoto = false;
          _errorMessage = 'Failed to select or upload image. Please try again.';
        });
      }
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final request = UpdateProfileRequest(
        fullName: _fullNameController.text,
        phoneNumber: _phoneNumberController.text,
        email: _emailController.text,
        jobTitle: _jobTitleController.text,
        company: _companyController.text,
        website: _websiteController.text,
        address: _addressController.text,
        bio: _bioController.text,
        profilePhotoUrl: _currentProfile.profilePhotoUrl,
      );

      final updatedProfile = await _profileService.updateMyProfile(request);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

      Navigator.of(context).pop(updatedProfile);
    } on ApiException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Failed to update profile. Please check your inputs and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedUrl = ApiConfig.resolveImageUrl(_currentProfile.profilePhotoUrl);
    final hasPhoto = _localImageFile != null || resolvedUrl != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_currentProfile);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Edit Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(_currentProfile),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_errorMessage.isNotEmpty)
                    ErrorBanner(
                      message: _errorMessage,
                      onDismiss: () => setState(() => _errorMessage = ''),
                    ),

                  // Top Circular Profile Photo / Avatar Picker
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 54,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              backgroundImage: _localImageFile != null
                                  ? FileImage(_localImageFile!) as ImageProvider
                                  : (resolvedUrl != null
                                      ? NetworkImage(resolvedUrl) as ImageProvider
                                      : null),
                              onBackgroundImageError: resolvedUrl != null
                                  ? (_, _) {}
                                  : null,
                              child: (!hasPhoto)
                                  ? Icon(
                                      Icons.person,
                                      size: 54,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                            ),
                            if (_isUploadingPhoto)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Material(
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                elevation: 3,
                                child: InkWell(
                                  onTap: _isUploadingPhoto ? null : _showPhotoOptionsSheet,
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(
                                      Icons.camera_alt,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _isUploadingPhoto ? null : _showPhotoOptionsSheet,
                          icon: Icon(
                            hasPhoto ? Icons.edit_outlined : Icons.add_a_photo_outlined,
                            size: 18,
                          ),
                          label: Text(
                            hasPhoto ? 'Change Photo' : 'Add Photo',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _fullNameController,
                    label: 'Full Name',
                    hint: 'e.g. John Doe',
                    prefixIcon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _emailController,
                    label: 'Email Address *',
                    hint: 'e.g. name@example.com',
                    prefixIcon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required.';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                        return 'Please enter a valid email address.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _phoneNumberController,
                    label: 'Phone Number',
                    hint: 'e.g. +1 555-0199',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _jobTitleController,
                    label: 'Job Title',
                    hint: 'e.g. Senior Software Architect',
                    prefixIcon: Icons.work_outline,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _companyController,
                    label: 'Company',
                    hint: 'e.g. Acme Corporation',
                    prefixIcon: Icons.business_outlined,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _websiteController,
                    label: 'Website',
                    hint: 'e.g. https://mywebsite.com',
                    prefixIcon: Icons.language_outlined,
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      if (value != null && value.trim().isNotEmpty) {
                        final url = value.trim();
                        if (!url.startsWith('http://') && !url.startsWith('https://')) {
                          return 'Website URL must begin with http:// or https://';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _addressController,
                    label: 'Address',
                    hint: 'e.g. San Francisco, CA',
                    prefixIcon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 16),

                  CustomTextField(
                    controller: _bioController,
                    label: 'Bio / About',
                    hint: 'Short description about yourself...',
                    prefixIcon: Icons.notes_outlined,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 28),

                  PrimaryButton(
                    text: 'Save Changes',
                    isLoading: _isLoading,
                    icon: Icons.check_circle_outline_rounded,
                    onPressed: _handleSave,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
