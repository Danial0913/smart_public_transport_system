import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:smart_public_transport_system/data/account_settings.dart';
import 'package:smart_public_transport_system/data/local_storage_service.dart';
import 'package:smart_public_transport_system/models/travel_preferences.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';
import 'account_storage_test.dart' show AccountDatabase;

class TravelDatabase extends AccountDatabase {
  final preferences = <int, Map<String, Object?>>{};
  final places = <Map<String, Object?>>[];
  int nextPlaceId = 1;
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
    if (table == 'travel_preferences') {
      expect(where, 'user_id = ?');
      final row = preferences[whereArgs!.first];
      return row == null ? [] : [Map.of(row)];
    }
    if (table == 'saved_places') {
      return places
          .where((place) {
            if (place['user_id'] != whereArgs!.first) return false;
            if (where == 'user_id = ?') return true;
            expect(where, 'user_id = ? AND label = ? AND id != ?');
            return (place['label'] as String).toLowerCase() ==
                    (whereArgs[1] as String).toLowerCase() &&
                place['id'] != whereArgs[2];
          })
          .map((place) => Map<String, Object?>.of(place))
          .toList();
    }
    return super.query(table, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'travel_preferences') {
      preferences[values['user_id'] as int] = Map.of(values);
      return 1;
    }
    if (table == 'saved_places') {
      final id = nextPlaceId++;
      places.add({'id': id, ...values});
      return id;
    }
    return super.insert(table, values);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'saved_places') {
      expect(where, 'id = ? AND user_id = ?');
      final matches = places.where(
        (row) => row['id'] == whereArgs![0] && row['user_id'] == whereArgs[1],
      );
      for (final row in matches) {
        row.addAll(values);
      }
      return matches.length;
    }
    return super.update(table, values, where: where, whereArgs: whereArgs);
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    if (table == 'saved_places') {
      expect(where, 'id = ? AND user_id = ?');
      final count = places.length;
      places.removeWhere(
        (row) => row['id'] == whereArgs![0] && row['user_id'] == whereArgs[1],
      );
      return count - places.length;
    }
    return super.delete(table, where: where, whereArgs: whereArgs);
  }
}

void main() {
  Future<void> login(LocalStorageService storage, int id) async {
    await storage.loginUser(
      email: 'rider$id@example.com',
      password: 'OldPassword1!',
    );
  }

  test(
    'Travel preferences persist for each account and map to real planner filters',
    () async {
      final database = TravelDatabase();
      final storage = LocalStorageService.forTesting(database);
      await login(storage, 1);
      const preferences = TravelPreferences(
        transportModes: {'Train', 'Ferry'},
        maximumWalkingMetres: 3500,
        preferLowestFare: false,
        preferFewerTransfers: true,
        travelNotifications: false,
      );
      await storage.saveTravelPreferences(preferences);
      final reopened = LocalStorageService.forTesting(database);
      await login(reopened, 1);
      final saved = await reopened.getTravelPreferences();
      expect(saved.plannerModes, {'MRT', 'LRT', 'KTM', 'Monorail', 'Ferry'});
      expect(saved.maximumWalkingMetres, 3500);
      expect(saved.routePreference, 'Recommended');
      expect(saved.preferFewerTransfers, true);
      expect(saved.travelNotifications, false);
      await login(reopened, 2);
      expect(
        (await reopened.getTravelPreferences()).toMap(),
        const TravelPreferences().toMap(),
      );
      await expectLater(
        reopened.saveTravelPreferences(
          const TravelPreferences(transportModes: {}),
        ),
        throwsA(isA<AccountSettingsException>()),
      );
      expect(const TravelPreferences().routePreference, 'Lowest Fee');
    },
  );

  test(
    'Saved places retain coordinates and cannot be edited or deleted by another account',
    () async {
      final database = TravelDatabase();
      final storage = LocalStorageService.forTesting(database);
      const location = JourneyLocation(
        name: 'Gurney Plaza',
        latitude: 5.4371,
        longitude: 100.3095,
      );
      await login(storage, 1);
      await storage.savePlace(label: ' Home ', location: location);
      final home = (await storage.getSavedPlaces()).single;
      expect(home.label, 'Home');
      expect(home.location.latitude, location.latitude);
      expect(home.location.longitude, location.longitude);
      await expectLater(
        storage.savePlace(label: 'home', location: location),
        throwsA(isA<AccountSettingsException>()),
      );
      await login(storage, 2);
      expect(await storage.getSavedPlaces(), isEmpty);
      await expectLater(
        storage.savePlace(id: home.id, label: 'Hijacked', location: location),
        throwsA(isA<AccountSettingsException>()),
      );
      await storage.deletePlace(home.id);
      await storage.savePlace(label: 'Home', location: location);
      expect(await storage.getSavedPlaces(), hasLength(1));
      final reopened = LocalStorageService.forTesting(database);
      await login(reopened, 1);
      expect((await reopened.getSavedPlaces()).single.label, 'Home');
      await reopened.savePlace(id: home.id, label: 'Work', location: location);
      expect((await reopened.getSavedPlaces()).single.label, 'Work');
      await reopened.deletePlace(home.id);
      expect(await reopened.getSavedPlaces(), isEmpty);
      await login(reopened, 2);
      expect((await reopened.getSavedPlaces()).single.label, 'Home');
    },
  );
}
