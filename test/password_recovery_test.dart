import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_public_transport_system/data/password_recovery_service.dart';
import 'package:smart_public_transport_system/screens/forgot_password_screen.dart';

RecoveryRequest challenge() => RecoveryRequest(
  id: 'request-1',
  sessionToken: 'private-session',
  email: 'rider@example.com',
  expiresAt: DateTime.now().add(const Duration(minutes: 10)),
  resendAt: DateTime.now().add(const Duration(minutes: 1)),
);

class FakeRecovery implements PasswordRecovery {
  bool failSend = false;
  bool linkVerified = false;
  String? savedPassword;
  int sends = 0;
  @override
  Future<RecoveryRequest> request(String email) async {
    sends++;
    if (failSend) throw const RecoveryException('Email delivery failed.');
    return challenge();
  }

  @override
  Future<RecoveryRequest> resend(RecoveryRequest request) =>
      this.request(request.email);
  @override
  Future<void> verifyOtp(RecoveryRequest request, String otp) async {
    if (otp != '123456') throw const RecoveryException('Invalid OTP.');
  }

  @override
  Future<bool> checkLink(RecoveryRequest request) async => linkVerified;
  @override
  Future<void> complete(RecoveryRequest request, String password) async {
    savedPassword = password;
  }
}

void main() {
  test('Missing server configuration never claims an email was sent', () async {
    var called = false;
    final service = PasswordRecoveryService(
      baseUrl: '',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
      accountExists: (_) async => true,
      updatePassword: (_, _) async {},
    );
    await expectLater(
      service.request('rider@example.com'),
      throwsA(isA<RecoveryException>()),
    );
    expect(called, isFalse);
  });

  test('Request normalizes email and rejects mail delivery failures', () async {
    final service = PasswordRecoveryService(
      baseUrl: 'https://recovery.example.com',
      client: MockClient((request) async {
        expect(jsonDecode(request.body)['email'], 'rider@example.com');
        return http.Response('{}', 503);
      }),
      accountExists: (email) async {
        expect(email, 'rider@example.com');
        return true;
      },
      updatePassword: (_, _) async {},
    );
    await expectLater(
      service.request(' Rider@Example.com '),
      throwsA(isA<RecoveryException>()),
    );
  });

  test('Rejected verification never changes the local password', () async {
    var writes = 0;
    final service = PasswordRecoveryService(
      baseUrl: 'https://recovery.example.com',
      client: MockClient((_) async => http.Response('{}', 400)),
      accountExists: (_) async => true,
      updatePassword: (_, _) async {
        writes++;
      },
    );
    await expectLater(
      service.complete(challenge(), 'NewPassword123!'),
      throwsA(isA<RecoveryException>()),
    );
    expect(writes, 0);
  });

  test('Reset is bound to the verified email and chosen password', () async {
    var writes = 0;
    var wrongEmail = true;
    final password = 'NewPassword123!';
    final digest = sha256.convert(utf8.encode(password)).toString();
    final service = PasswordRecoveryService(
      baseUrl: 'https://recovery.example.com',
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['sessionToken'], 'private-session');
        expect(body['passwordDigest'], digest);
        expect(request.body.contains(password), isFalse);
        return http.Response(
          jsonEncode({
            'completed': true,
            'email': wrongEmail ? 'other@example.com' : 'rider@example.com',
            'passwordDigest': digest,
          }),
          200,
        );
      }),
      accountExists: (_) async => true,
      updatePassword: (email, value) async {
        expect(email, 'rider@example.com');
        expect(value, password);
        writes++;
      },
    );
    await expectLater(
      service.complete(challenge(), password),
      throwsA(isA<RecoveryException>()),
    );
    expect(writes, 0);
    wrongEmail = false;
    await service.complete(challenge(), password);
    expect(writes, 1);
  });

  testWidgets('OTP flow validates code and passwords before showing success', (
    tester,
  ) async {
    final recovery = FakeRecovery();
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(recovery: recovery)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-email')),
      'rider@example.com',
    );
    await tester.tap(find.text('Send Link and OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Check Your Email'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-otp')),
      '000000',
    );
    await tester.tap(find.text('Verify OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid OTP.'), findsOneWidget);
    expect(find.text('Create a New Password'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-otp')),
      '123456',
    );
    await tester.tap(find.text('Verify OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('recovery-password')),
      'NewPassword123!',
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-confirmation')),
      'Different123',
    );
    await tester.ensureVisible(find.text('Update Password'));
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(recovery.savedPassword, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('recovery-confirmation')),
      'NewPassword123!',
    );
    await tester.tap(find.text('Update Password'));
    await tester.pumpAndSettle();
    expect(find.text('Password Updated'), findsOneWidget);
    expect(recovery.savedPassword, 'NewPassword123!');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Email-link path requires server confirmation', (tester) async {
    final recovery = FakeRecovery();
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(recovery: recovery)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-email')),
      'rider@example.com',
    );
    await tester.tap(find.text('Send Link and OTP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("I've Confirmed the Email Link"));
    await tester.pumpAndSettle();
    expect(find.text('Create a New Password'), findsNothing);
    recovery.linkVerified = true;
    await tester.tap(find.text("I've Confirmed the Email Link"));
    await tester.pumpAndSettle();
    expect(find.text('Create a New Password'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Send failures leave the form available without false success', (
    tester,
  ) async {
    final recovery = FakeRecovery()..failSend = true;
    await tester.pumpWidget(
      MaterialApp(home: ForgotPasswordScreen(recovery: recovery)),
    );
    await tester.enterText(
      find.byKey(const ValueKey('recovery-email')),
      'rider@example.com',
    );
    await tester.tap(find.text('Send Link and OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Email delivery failed.'), findsOneWidget);
    expect(find.text('Check Your Email'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
