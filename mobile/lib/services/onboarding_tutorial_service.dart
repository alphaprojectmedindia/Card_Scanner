import 'package:flutter/foundation.dart';
import 'secure_storage_service.dart';

/// Service managing the onboarding guided tour state and per-user persistence.
class OnboardingTutorialService {
  static final OnboardingTutorialService instance = OnboardingTutorialService._internal();
  factory OnboardingTutorialService({SecureStorageService? storageService}) {
    if (storageService != null) {
      instance._storageService = storageService;
    }
    return instance;
  }
  OnboardingTutorialService._internal({SecureStorageService? storageService})
      : _storageService = storageService ?? SecureStorageService();

  SecureStorageService _storageService;

  void setStorageForTesting(SecureStorageService storage) {
    _storageService = storage;
  }

  /// ValueNotifier allowing settings or profile screens to trigger an immediate tour start on the home dashboard.
  final ValueNotifier<bool> shouldStartTourNotifier = ValueNotifier<bool>(false);

  void requestTourStart() {
    shouldStartTourNotifier.value = true;
  }

  /// Whether the interactive onboarding tour is currently actively showing.
  bool isTourActive = false;

  /// Checks whether the guided tutorial should automatically start for a given user.
  /// Returns `true` only if the user has NOT previously completed or dismissed it.
  Future<bool> shouldShowTutorial(String? userId) async {
    final effectiveId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (await _storageService.getUserId() ?? 'default_user');
    try {
      final isCompleted = await _storageService.isOnboardingCompleted(effectiveId);
      return !isCompleted;
    } catch (_) {
      return false;
    }
  }

  /// Records that the user has completed or dismissed the onboarding tutorial.
  Future<void> markCompleted(String? userId) async {
    final effectiveId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (await _storageService.getUserId() ?? 'default_user');
    try {
      await _storageService.setOnboardingCompleted(effectiveId, completed: true);
    } catch (_) {}
  }

  /// Checks whether the QR generator tour has been completed.
  Future<bool> isQrTourCompleted(String? userId) async {
    final effectiveId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (await _storageService.getUserId() ?? 'default_user');
    try {
      final isCompleted = await _storageService.getString('qr_tour_completed_$effectiveId');
      return isCompleted == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Marks the QR generator tour as completed.
  Future<void> markQrTourCompleted(String? userId) async {
    final effectiveId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (await _storageService.getUserId() ?? 'default_user');
    try {
      await _storageService.setString('qr_tour_completed_$effectiveId', 'true');
    } catch (_) {}
  }

  /// Resets the tutorial completion status for the user, allowing it to be re-run.
  Future<void> resetTutorial(String? userId) async {
    final effectiveId = (userId != null && userId.trim().isNotEmpty)
        ? userId.trim()
        : (await _storageService.getUserId() ?? 'default_user');
    try {
      await _storageService.setOnboardingCompleted(effectiveId, completed: false);
      await _storageService.delete('qr_tour_completed_$effectiveId');
    } catch (_) {}
  }
}
