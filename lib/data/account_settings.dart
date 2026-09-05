import 'package:flutter/foundation.dart';
import '../models/user_models.dart';

class AccountSettingsException implements Exception {
  const AccountSettingsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class LoginAttemptException implements Exception {
  const LoginAttemptException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AccountSettings {
  ValueListenable<AppUser?> get currentUser;
  Future<void> updateProfile({
    required String fullName,
    required String email,
    required String phone,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<bool> getSearchHistoryEnabled();
  Future<void> setSearchHistoryEnabled(bool enabled);
  Future<void> clearRecentSearches();
  void logout();
}

String? validateProfileName(String? value) =>
    value == null || value.trim().length < 2 || value.trim().length > 100
    ? 'Enter a name between 2 and 100 characters.'
    : null;

String? validateProfileEmail(String? value) =>
    value == null ||
        value.trim().length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())
    ? 'Enter a valid email address.'
    : null;

String? validateProfilePhone(String? value) =>
    value == null ||
        !RegExp(
          r'^(?:\+?60|0)(?:11[0-9]{8}|1[0-9]{7,8})$',
        ).hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''))
    ? 'Enter a valid Malaysian phone number.'
    : null;
