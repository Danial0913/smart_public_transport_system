import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'local_storage_service.dart';
import 'password_policy.dart';

class RecoveryException implements Exception {
  const RecoveryException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RecoveryRequest {
  const RecoveryRequest({
    required this.id,
    required this.sessionToken,
    required this.email,
    required this.expiresAt,
    required this.resendAt,
  });
  final String id;
  final String sessionToken;
  final String email;
  final DateTime expiresAt;
  final DateTime resendAt;
}

abstract class PasswordRecovery {
  Future<RecoveryRequest> request(String email);
  Future<RecoveryRequest> resend(RecoveryRequest request);
  Future<void> verifyOtp(RecoveryRequest request, String otp);
  Future<bool> checkLink(RecoveryRequest request);
  Future<void> complete(RecoveryRequest request, String password);
}

class PasswordRecoveryService implements PasswordRecovery {
  PasswordRecoveryService({
    required this.baseUrl,
    required this.client,
    required this.accountExists,
    required this.updatePassword,
  });

  static final instance = PasswordRecoveryService(
    baseUrl: const String.fromEnvironment('PASSWORD_RECOVERY_URL').isNotEmpty
        ? const String.fromEnvironment('PASSWORD_RECOVERY_URL')
        : kDebugMode
        ? 'http://127.0.0.1:8787'
        : '',
    client: http.Client(),
    accountExists: LocalStorageService.instance.emailExists,
    updatePassword: LocalStorageService.instance.updateRecoveredPassword,
  );

  final String baseUrl;
  final http.Client client;
  final Future<bool> Function(String) accountExists;
  final Future<void> Function(String, String) updatePassword;

  Uri _endpoint(String path) {
    final uri = Uri.tryParse(baseUrl);
    final debugLoopback =
        kDebugMode &&
        uri?.scheme == 'http' &&
        const {'127.0.0.1', 'localhost', '10.0.2.2'}.contains(uri?.host);
    if (uri == null ||
        (uri.scheme != 'https' && !debugLoopback) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const RecoveryException(
        'Email recovery is not available yet. Please contact support.',
      );
    }
    return uri.replace(
      path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/v1/recovery/$path',
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await client
          .post(
            _endpoint(path),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 35));
      if (response.statusCode == 429) {
        throw const RecoveryException(
          'Too many attempts. Please wait before trying again.',
        );
      }
      if (response.statusCode >= 500) {
        throw const RecoveryException(
          'The recovery service could not complete the request. Please try again later.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const RecoveryException(
          'The code or link is invalid, expired, or already used. Check your latest email or request a new one.',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on RecoveryException {
      rethrow;
    } on TimeoutException {
      throw const RecoveryException(
        'The request timed out. Check your connection and try again.',
      );
    } catch (_) {
      final localServer = const {
        '127.0.0.1',
        'localhost',
        '10.0.2.2',
      }.contains(Uri.tryParse(baseUrl)?.host);
      throw RecoveryException(
        kDebugMode && localServer
            ? 'Could not reach the local recovery server. This development build needs a server running on the connected computer. Shared builds need a public HTTPS recovery server.'
            : 'Could not reach the recovery service. Please try again.',
      );
    }
  }

  Map<String, dynamic> _session(RecoveryRequest request) => {
    'requestId': request.id,
    'sessionToken': request.sessionToken,
  };

  RecoveryRequest _parseRequest(Map<String, dynamic> data, String email) {
    final now = DateTime.now();
    try {
      return RecoveryRequest(
        id: data['requestId'] as String,
        sessionToken: data['sessionToken'] as String,
        email: email,
        expiresAt: now.add(Duration(seconds: data['expiresIn'] as int)),
        resendAt: now.add(Duration(seconds: data['resendAfter'] as int)),
      );
    } catch (_) {
      throw const RecoveryException(
        'The recovery service returned an invalid response. Please try again.',
      );
    }
  }

  @override
  Future<RecoveryRequest> request(String email) async {
    _endpoint('request');
    final normalized = email.trim().toLowerCase();
    if (!await accountExists(normalized)) {
      throw const RecoveryException(
        'Use the email for an account registered on this device.',
      );
    }
    return _parseRequest(
      await _post('request', {'email': normalized}),
      normalized,
    );
  }

  @override
  Future<RecoveryRequest> resend(RecoveryRequest request) async =>
      _parseRequest(await _post('resend', _session(request)), request.email);

  @override
  Future<void> verifyOtp(RecoveryRequest request, String otp) async {
    final data = await _post('verify', {
      ..._session(request),
      'otp': otp.trim(),
    });
    if (data['verified'] != true) {
      throw const RecoveryException('The code could not be verified.');
    }
  }

  @override
  Future<bool> checkLink(RecoveryRequest request) async =>
      (await _post('status', _session(request)))['verified'] == true;

  @override
  Future<void> complete(RecoveryRequest request, String password) async {
    final validation = validateNewPassword(password);
    if (validation != null) throw RecoveryException(validation);
    final digest = sha256.convert(utf8.encode(password)).toString();
    final data = await _post('complete', {
      ..._session(request),
      'passwordDigest': digest,
    });
    if (data['completed'] != true ||
        data['email'] != request.email ||
        data['passwordDigest'] != digest) {
      throw const RecoveryException(
        'Password recovery could not be verified for this account.',
      );
    }
    await updatePassword(request.email, password);
  }
}
