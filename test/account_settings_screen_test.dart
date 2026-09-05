import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transport_system/data/account_settings.dart';
import 'package:smart_public_transport_system/models/user_models.dart';
import 'package:smart_public_transport_system/screens/account_form_screen.dart';
import 'package:smart_public_transport_system/screens/privacy_security_screen.dart';
import 'package:smart_public_transport_system/screens/profile_screen.dart';

class FakeAccount implements AccountSettings {
  @override
  final ValueNotifier<AppUser?> currentUser = ValueNotifier<AppUser?>(
    AppUser(
      id: 7,
      fullName: 'Test Rider',
      email: 'rider@example.com',
      phone: '0123456789',
      createdAt: DateTime(2026),
    ),
  );
  bool searches = true;
  bool failSave = false;
  int clears = 0;
  String? newPassword;

  @override
  Future<void> updateProfile({
    required String fullName,
    required String email,
    required String phone,
  }) async {
    final user = currentUser.value!;
    currentUser.value = AppUser(
      id: user.id,
      fullName: fullName,
      email: email,
      phone: phone,
      createdAt: user.createdAt,
    );
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword != 'OldPassword1!') {
      throw const AccountSettingsException(
        'Your current password is incorrect.',
      );
    }
    this.newPassword = newPassword;
  }

  @override
  Future<bool> getSearchHistoryEnabled() async => searches;
  @override
  Future<void> setSearchHistoryEnabled(bool enabled) async {
    if (failSave) throw StateError('Storage unavailable');
    searches = enabled;
  }

  @override
  Future<void> clearRecentSearches() async {
    clears++;
  }

  @override
  void logout() => currentUser.value = null;
}

Future<void> tapVisible(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Profile edits save without a password field and refresh the profile header',
    (tester) async {
      final account = FakeAccount();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileScreen(account: account)),
        ),
      );
      expect(find.text('rider@example.com'), findsOneWidget);
      await tapVisible(tester, 'Edit Profile');
      await tester.enterText(
        find.byKey(const ValueKey('profile-name')),
        'Updated Rider',
      );
      await tester.enterText(
        find.byKey(const ValueKey('profile-email')),
        'updated@example.com',
      );
      expect(find.byKey(const ValueKey('current-password')), findsNothing);
      await tapVisible(tester, 'Save Changes');
      expect(find.text('Updated Rider'), findsOneWidget);
      expect(find.text('updated@example.com'), findsOneWidget);
    },
  );

  testWidgets(
    'Change password rejects missing character types, mismatch and incorrect current password',
    (tester) async {
      final account = FakeAccount();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AccountFormScreen(
                      account: account,
                      changePassword: true,
                    ),
                  ),
                ),
                child: const Text('Open password form'),
              ),
            ),
          ),
        ),
      );
      await tapVisible(tester, 'Open password form');
      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'WrongPassword1!',
      );
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'NewPassword123',
      );
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'NewPassword123',
      );
      await tapVisible(tester, 'Update Password');
      expect(
        find.textContaining('Password must contain at least one special'),
        findsOneWidget,
      );
      expect(account.newPassword, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('new-password')),
        'NewPassword123!',
      );
      await tapVisible(tester, 'Update Password');
      expect(find.text('Passwords do not match.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('confirm-password')),
        'NewPassword123!',
      );
      await tapVisible(tester, 'Update Password');
      expect(find.text('Your current password is incorrect.'), findsOneWidget);
      expect(account.newPassword, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('current-password')),
        'OldPassword1!',
      );
      await tapVisible(tester, 'Update Password');
      expect(account.newPassword, 'NewPassword123!');
      expect(find.text('Open password form'), findsOneWidget);
    },
  );

  testWidgets(
    'Privacy switch persists and a failed save does not change the displayed setting',
    (tester) async {
      final account = FakeAccount();
      Future<void> open() async {
        await tester.pumpWidget(
          MaterialApp(home: PrivacySecurityScreen(account: account)),
        );
        await tester.pumpAndSettle();
      }

      await open();
      account.failSave = true;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        true,
      );
      account.failSave = false;
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(account.searches, false);
      await tester.pumpWidget(const SizedBox());
      await open();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tapVisible(tester, 'Clear recent searches');
      await tapVisible(tester, 'Cancel');
      expect(account.clears, 0);
      await tapVisible(tester, 'Clear recent searches');
      await tapVisible(tester, 'Clear Searches');
      expect(account.clears, 1);
    },
  );
}
