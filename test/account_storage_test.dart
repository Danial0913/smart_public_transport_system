import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smart_public_transport_system/data/account_settings.dart';
import 'package:smart_public_transport_system/data/local_storage_service.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';

String hash(String value) => sha256.convert(utf8.encode(value)).toString();

// Database boundary fake: exercises the real storage/authentication methods.
class AccountDatabase extends Fake implements Database, Transaction {
  final users = [
    for (final id in [1, 2])
      <String, Object?>{
        'id': id,
        'full_name': 'Rider $id',
        'email': 'rider$id@example.com',
        'phone': '0123456789',
        'password_hash': hash('OldPassword1!'),
        'created_at': '2026-01-01T00:00:00.000',
      },
  ];
  bool? saveSearches;
  int searchWrites = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => action(this);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    if (table == 'privacy_settings') {
      return saveSearches == null
          ? []
          : [
              {'id': 1, 'save_searches': saveSearches! ? 1 : 0},
            ];
    }
    expect(table, 'users');
    return users
        .where(
          (row) => switch (where) {
            'id = ?' => row['id'] == whereArgs![0],
            'email = ?' => row['email'] == whereArgs![0],
            'email = ? AND id != ?' =>
              row['email'] == whereArgs![0] && row['id'] != whereArgs[1],
            _ => throw StateError('Unexpected query'),
          },
        )
        .map((row) => Map<String, Object?>.of(row))
        .toList();
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    expect(table, 'users');
    expect(where, 'id = ?');
    final row = users.singleWhere((row) => row['id'] == whereArgs!.single);
    row.addAll(values);
    return 1;
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'privacy_settings') {
      saveSearches = values['save_searches'] == 1;
    } else {
      expect(table, 'recent_searches');
      searchWrites++;
    }
    return 1;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async => 0;
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;
}

void main() {
  test(
    'Profile edits require a signed-in account and reject duplicate emails',
    () async {
      final database = AccountDatabase();
      final storage = LocalStorageService.forTesting(database);
      Future<void> edit(String email) => storage.updateProfile(
        fullName: 'Updated Rider',
        email: email,
        phone: '0123456789',
      );
      await expectLater(
        edit('updated@example.com'),
        throwsA(isA<AccountSettingsException>()),
      );
      await storage.loginUser(
        email: 'rider1@example.com',
        password: 'OldPassword1!',
      );
      await expectLater(
        edit('rider2@example.com'),
        throwsA(isA<AccountSettingsException>()),
      );
      expect(database.users.first['email'], 'rider1@example.com');
      await edit(' Updated@Example.com ');
      expect(storage.currentUser.value!.email, 'updated@example.com');
      expect(database.users[1]['email'], 'rider2@example.com');
      expect(
        await storage.loginUser(
          email: 'rider1@example.com',
          password: 'OldPassword1!',
        ),
        isNull,
      );
      expect(
        await storage.loginUser(
          email: 'updated@example.com',
          password: 'OldPassword1!',
        ),
        isNotNull,
      );
      storage.logout();
      expect(storage.currentUser.value, isNull);
    },
  );

  test(
    'Password change rejects the wrong current password and replaces only this account hash',
    () async {
      final database = AccountDatabase();
      final storage = LocalStorageService.forTesting(database);
      await storage.loginUser(
        email: 'rider1@example.com',
        password: 'OldPassword1!',
      );
      await expectLater(
        storage.changePassword(
          currentPassword: 'wrong',
          newPassword: 'NewPassword1!',
        ),
        throwsA(isA<AccountSettingsException>()),
      );
      expect(database.users.first['password_hash'], hash('OldPassword1!'));
      await storage.changePassword(
        currentPassword: 'OldPassword1!',
        newPassword: 'NewPassword1!',
      );
      expect(database.users.first['password_hash'], hash('NewPassword1!'));
      expect(database.users[1]['password_hash'], hash('OldPassword1!'));
      expect(
        await storage.loginUser(
          email: 'rider1@example.com',
          password: 'OldPassword1!',
        ),
        isNull,
      );
      expect(
        await storage.loginUser(
          email: 'rider1@example.com',
          password: 'NewPassword1!',
        ),
        isNotNull,
      );
    },
  );

  test(
    'Persisted privacy preference prevents future search recording',
    () async {
      final database = AccountDatabase();
      final storage = LocalStorageService.forTesting(database);
      const origin = JourneyLocation(
        name: 'Origin',
        latitude: 5.4,
        longitude: 100.3,
      );
      const destination = JourneyLocation(
        name: 'Destination',
        latitude: 5.3,
        longitude: 100.4,
      );
      await storage.recordSearch(origin: origin, destination: destination);
      expect(database.searchWrites, 1);
      await storage.setSearchHistoryEnabled(false);
      final reopened = LocalStorageService.forTesting(database);
      expect(await reopened.getSearchHistoryEnabled(), false);
      await reopened.recordSearch(origin: origin, destination: destination);
      expect(database.searchWrites, 1);
      await reopened.setSearchHistoryEnabled(true);
      await reopened.recordSearch(origin: origin, destination: destination);
      expect(database.searchWrites, 2);
    },
  );
}
