import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/api_config.dart';
import '../../models/update_profile_request.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/pending_profile_photo_store.dart';
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

class _EditProfileScreenState extends State<EditProfileScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLostDataAndUpload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkLostDataAndUpload();
    }
  }

  /// Recovers image data if Android killed or recreated MainActivity while the external
  /// camera app was active.
  Future<void> _checkLostDataAndUpload() async {
    if (_isUploadingPhoto || PendingProfilePhotoStore.isUploadInProgress) {
      return;
    }

    final pending = await PendingProfilePhotoStore.loadPendingCapture();
    if (pending == null) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] lost-data recovery attempted');
    }

    try {
      final LostDataResponse response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] lost-data recovery returned empty');
        }
        await PendingProfilePhotoStore.clear();
        return;
      }

      if (response.exception != null) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] lost-data recovery failed: ${response.exception?.message}');
        }
        await PendingProfilePhotoStore.clear();
        if (mounted) {
          setState(() {
            _errorMessage = response.exception?.message ?? 'Failed to recover captured photo.';
          });
        }
        return;
      }

      final recoveredFile = response.file ??
          (response.files != null && response.files!.isNotEmpty ? response.files!.first : null);

      if (recoveredFile == null) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] lost-data recovery returned null file');
        }
        await PendingProfilePhotoStore.clear();
        return;
      }

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] lost-data recovery succeeded: ${recoveredFile.path}');
      }

      await _processAndUploadFile(recoveredFile);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] lost-data recovery exception: $e');
      }
      await PendingProfilePhotoStore.clear();
    }
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
    if (_isUploadingPhoto || PendingProfilePhotoStore.isUploadInProgress) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] Change Photo tapped');
      debugPrint('[ProfilePhotoFlow] source selected: ${source.name}');
      debugPrint('[ProfilePhotoFlow] picker starting');
    }

    await PendingProfilePhotoStore.savePendingCapture(source: source.name);

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] picker returned null, checking lost-data...');
        }
        final LostDataResponse lostData = await _imagePicker.retrieveLostData();
        if (!lostData.isEmpty && lostData.file != null) {
          if (kDebugMode) {
            debugPrint('[ProfilePhotoFlow] lost-data recovered after null picker: ${lostData.file!.path}');
          }
          await _processAndUploadFile(lostData.file!);
          return;
        }

        if (kDebugMode) {
          debugPrint('[ProfilePhotoFlow] picker returned null (user cancelled)');
        }
        await PendingProfilePhotoStore.clear();
        return;
      }

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] picker returned normally: ${pickedFile.path}');
      }

      await _processAndUploadFile(pickedFile);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] picker error: $e');
      }
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
          _errorMessage = 'Failed to select or upload image. Please try again.';
        });
      }
    }
  }

  Future<void> _processAndUploadFile(XFile xFile) async {
    if (_isUploadingPhoto || PendingProfilePhotoStore.isUploadInProgress) {
      return;
    }

    if (PendingProfilePhotoStore.lastUploadedPath == xFile.path) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] Skipping duplicate upload for path: ${xFile.path}');
      }
      await PendingProfilePhotoStore.clear();
      return;
    }

    final rawFile = File(xFile.path);
    final fileExists = rawFile.existsSync();
    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] XFile path: ${xFile.path}');
      debugPrint('[ProfilePhotoFlow] whether file exists: $fileExists');
    }

    if (!fileExists) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _errorMessage = 'The captured image file could not be found. Please try again.';
        });
      }
      return;
    }

    final fileSize = rawFile.lengthSync();
    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] file size: $fileSize bytes');
    }

    if (fileSize == 0) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _errorMessage = 'The captured image is empty (0 bytes). Please take another photo.';
        });
      }
      return;
    }

    const maxPhotoSizeBytes = 5 * 1024 * 1024; // 5 MB
    if (fileSize > maxPhotoSizeBytes) {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _errorMessage = 'Selected image exceeds the 5 MB limit. Please select a smaller photo.';
        });
      }
      return;
    }

    // Determine extension and MIME type safely
    final extension = xFile.path.contains('.')
        ? xFile.path.split('.').last.toLowerCase()
        : 'jpg';
    String contentType = 'image/jpeg';
    if (extension == 'png') {
      contentType = 'image/png';
    } else if (extension == 'webp') {
      contentType = 'image/webp';
    } else if (extension == 'gif') {
      contentType = 'image/gif';
    } else if (extension != 'jpg' && extension != 'jpeg') {
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _errorMessage = 'Unsupported image format ($extension). Please use JPEG, PNG, WebP, or GIF.';
        });
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] MIME/extension: $contentType / .$extension');
    }

    // Stage file into systemTemp to guard against Android cache cleanup during upload
    File uploadFile = rawFile;
    File? tempStagedFile;
    try {
      final tempDir = Directory.systemTemp.path;
      final stagedPath = '$tempDir/profile_photo_staged_${DateTime.now().millisecondsSinceEpoch}.$extension';
      tempStagedFile = rawFile.copySync(stagedPath);
      uploadFile = tempStagedFile;
    } catch (_) {
      uploadFile = rawFile;
    }

    setState(() {
      _localImageFile = uploadFile;
      _isUploadingPhoto = true;
      _errorMessage = '';
    });
    PendingProfilePhotoStore.markUploadInProgress(true);

    if (kDebugMode) {
      debugPrint('[ProfilePhotoFlow] upload starting');
      debugPrint('[ProfilePhotoFlow] HTTP method: POST');
      debugPrint('[ProfilePhotoFlow] endpoint path: ${ApiConfig.uploadProfilePhotoEndpoint}');
      debugPrint('[ProfilePhotoFlow] multipart field name: file');
    }

    try {
      final updatedProfile = await _profileService.uploadProfilePhoto(
        filePath: uploadFile.path,
        filename: xFile.name.isNotEmpty ? xFile.name : 'profile_photo.$extension',
        contentType: contentType,
      );

      PendingProfilePhotoStore.lastUploadedPath = xFile.path;
      await PendingProfilePhotoStore.clear();

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] response success: 200 OK');
        debugPrint('[ProfilePhotoFlow] returned profile photo URL: ${updatedProfile.profilePhotoUrl}');
      }

      // Evict old photo from cache if present
      final oldResolvedUrl = ApiConfig.resolveImageUrl(_currentProfile.profilePhotoUrl);
      if (oldResolvedUrl != null) {
        PaintingBinding.instance.imageCache.evict(NetworkImage(oldResolvedUrl));
      }

      if (!mounted) return;

      setState(() {
        _currentProfile = updatedProfile;
        _isUploadingPhoto = false;
      });

      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] displayed photo URL/reference: ${_currentProfile.profilePhotoUrl}');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile photo uploaded successfully!'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } on ApiException catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] response failure: ${e.statusCode} ${e.message}');
      }
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _localImageFile = null;
          _isUploadingPhoto = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ProfilePhotoFlow] unexpected error during upload: $e');
      }
      await PendingProfilePhotoStore.clear();
      if (mounted) {
        setState(() {
          _localImageFile = null;
          _isUploadingPhoto = false;
          _errorMessage = 'Could not update profile photo. Please try again.';
        });
      }
    } finally {
      PendingProfilePhotoStore.markUploadInProgress(false);
      if (tempStagedFile != null && tempStagedFile.existsSync()) {
        try {
          tempStagedFile.deleteSync();
        } catch (_) {}
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
