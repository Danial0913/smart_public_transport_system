import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_public_transport_system/data/local_storage_service.dart';
import 'package:smart_public_transport_system/data/password_policy.dart';
import 'package:smart_public_transport_system/data/password_recovery_service.dart';

void main() {
  final invalidPasswords = <String>[
    '',
    'Aa1!', // Too short.
    'Aa1!${'a' * 125}', // Over the maximum length.
    'PASSWORD1!', // No lowercase letter.
    'password1!', // No uppercase letter.
    'Password!!', // No number.
    'Password12', // No special character.
    'Password1 ', // A space does not satisfy the special-character rule.
  ];

  test(
    'New passwords require all four character types within length limits',
    () {
      expect(validateNewPassword(null), isNotNull);
      for (final password in invalidPasswords) {
        expect(validateNewPassword(password), isNotNull);
      }
      for (final password in [
        'Pass123!',
        'Password1_',
        'Password1@',
        'Aa1!${'a' * 124}',
      ]) {
        expect(validateNewPassword(password), isNull);
      }
    },
  );

  test(
    'Invalid recovery passwords never reach the server or local storage',
    () async {
      var requests = 0;
      var writes = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      addTearDown(client.close);
      final service = PasswordRecoveryService(
        baseUrl: 'https://recovery.example.com',
        client: client,
        accountExists: (_) async => true,
        updatePassword: (_, _) async {
          writes++;
        },
      );
      final request = RecoveryRequest(
        id: 'test-request',
        sessionToken: 'test-session',
        email: 'rider@example.com',
        expiresAt: DateTime.now().add(const Duration(minutes: 10)),
        resendAt: DateTime.now(),
      );
      for (final password in invalidPasswords) {
        await expectLater(
          service.complete(request, password),
          throwsA(isA<RecoveryException>()),
        );
      }
      expect(requests, 0);
      expect(writes, 0);
    },
  );

  test(
    'Registration and recovered-password writes enforce the same policy',
    () async {
      final storage = LocalStorageService.instance;
      for (final password in invalidPasswords) {
        await expectLater(
          storage.registerUser(
            fullName: 'Test Rider',
            email: 'rider@example.com',
            phone: '0123456789',
            password: password,
          ),
          throwsArgumentError,
        );
        await expectLater(
          storage.updateRecoveredPassword('rider@example.com', password),
          throwsArgumentError,
        );
      }
    },
  );
}
