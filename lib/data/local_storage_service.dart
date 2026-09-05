import 'dart:convert';
import 'password_policy.dart';
import 'account_settings.dart';
import 'travel_settings.dart';
import 'location_service.dart';
import '../models/travel_preferences.dart';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import '../models/accessibility_models.dart';
import '../models/transit_models.dart';
import '../models/travel_history_models.dart';
import '../models/user_models.dart';

class LocalStorageService implements AccountSettings, TravelSettings {
  static const _maximumLoginFailures = 5;
  static const _loginLockDuration = Duration(minutes: 15);

  LocalStorageService._() : _nowForTesting = null;

  @visibleForTesting
  LocalStorageService.forTesting(Database database, {DateTime Function()? now})
    : _database = database,
      _nowForTesting = now;

  static final LocalStorageService instance = LocalStorageService._();

  Database? _database;
  final DateTime Function()? _nowForTesting;
  final ValueNotifier<AppUser?> _currentUser = ValueNotifier(null);
  @override
  ValueListenable<AppUser?> get currentUser => _currentUser;

  @override
  void logout() => _currentUser.value = null;

  Future<void> initialise() async {
    if (_database != null) return;

    final databasePath = path.join(
      await getDatabasesPath(),
      'smart_public_transport.db',
    );

    _database = await openDatabase(
      databasePath,
      version: 13,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name TEXT NOT NULL,
          email TEXT NOT NULL COLLATE NOCASE UNIQUE,
          phone TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
        await _createUserScopedDataTables(database);
        await _createTravelSettingsTables(database);
        await _createLoginAttemptsTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN origin_latitude REAL',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN origin_longitude REAL',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN destination_latitude REAL',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN destination_longitude REAL',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN origin_latitude REAL',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN origin_longitude REAL',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN destination_latitude REAL',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN destination_longitude REAL',
          );
        }
        if (oldVersion < 4) {
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN known_fare REAL',
          );
          await database.execute(
            "ALTER TABLE saved_journeys ADD COLUMN route_ids TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            "ALTER TABLE saved_journeys ADD COLUMN modes TEXT NOT NULL DEFAULT '[]'",
          );
          await database.execute(
            "ALTER TABLE saved_journeys ADD COLUMN preference TEXT NOT NULL DEFAULT 'Recommended'",
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN depart_at INTEGER NOT NULL DEFAULT 1',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN maximum_walking_metres INTEGER NOT NULL DEFAULT 2000',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN accessible_only INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN fewer_transfers INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN walking_metres INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE saved_journeys ADD COLUMN transfer_count INTEGER NOT NULL DEFAULT 0',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN requested_time TEXT',
          );
          await database.execute(
            'ALTER TABLE recent_searches ADD COLUMN preference TEXT',
          );
        }
        if (oldVersion < 5) {
          await database.execute('''
            DELETE FROM favourites
            WHERE rowid NOT IN (
              SELECT MAX(rowid) FROM favourites GROUP BY type, reference_id
            )
          ''');
          await database.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS favourites_reference_unique '
            'ON favourites(type, reference_id)',
          );
        }
        if (oldVersion < 7) {
          // GTFS snapshots are bundled JSON assets now, so downloaded cache
          // rows are obsolete and only consume device storage.
          await database.execute('DROP TABLE IF EXISTS gtfs_cache_chunks');
          await database.execute('DROP TABLE IF EXISTS gtfs_cache');
        }
        if (oldVersion < 8) {
          await database.execute('''
          CREATE TABLE IF NOT EXISTS users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          full_name TEXT NOT NULL,
          email TEXT NOT NULL COLLATE NOCASE UNIQUE,
          phone TEXT NOT NULL,
          password_hash TEXT NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
        }
        if (oldVersion < 9) {
          await _createEndedJourneyRunsTable(database);
        }
        if (oldVersion < 10) {
          await _createPrivacySettingsTable(database);
        }
        if (oldVersion < 11) {
          await _createTravelSettingsTables(database);
        }
        if (oldVersion < 12) {
          await _migratePersonalDataToUsers(database);
        }
        if (oldVersion < 13) {
          await _createLoginAttemptsTable(database);
        }
      },
    );
  }

  Future<Database> get _db async {
    await initialise();
    return _database!;
  }

  Future<void> saveJourney(
    JourneyOption option, {
    String preference = 'Recommended',
    bool departAt = true,
    int maximumWalkingMetres = 2000,
    bool accessibleOnly = false,
    bool fewerTransfers = false,
  }) async {
    await updateSavedJourney(
      SavedJourney.fromOption(
        option,
        preference: preference,
        departAt: departAt,
        maximumWalkingMetres: maximumWalkingMetres,
        accessibleOnly: accessibleOnly,
        fewerTransfers: fewerTransfers,
      ),
    );
  }

  Future<void> updateSavedJourney(SavedJourney journey) async {
    final user = _signedInUser();
    final database = await _db;
    await database.insert(
      'saved_journeys',
      _savedJourneyToDatabaseMap(journey, user.id),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isJourneySaved(String id) async {
    final user = _signedInUser();
    final database = await _db;
    final result = await database.query(
      'saved_journeys',
      columns: ['id'],
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<SavedJourney>> getSavedJourneys() async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'saved_journeys',
      where: 'user_id = ?',
      whereArgs: [user.id],
      orderBy: 'saved_at DESC',
    );
    return rows.map(_savedJourneyFromDatabaseMap).toList();
  }

  Future<void> deleteSavedJourney(String id) async {
    final user = _signedInUser();
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete(
        'favourites',
        where: 'user_id = ? AND type = ? AND reference_id = ?',
        whereArgs: [user.id, 'Journey', id],
      );
      await transaction.delete(
        'saved_journeys',
        where: 'user_id = ? AND id = ?',
        whereArgs: [user.id, id],
      );
    });
  }

  Future<Set<String>> getEndedJourneyRunKeys() async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'ended_journey_runs',
      columns: ['journey_id', 'departure_time'],
      where: 'user_id = ?',
      whereArgs: [user.id],
    );
    return rows
        .map(
          (row) => _journeyRunKey(
            row['journey_id'] as String,
            DateTime.parse(row['departure_time'] as String),
          ),
        )
        .toSet();
  }

  Future<void> markJourneyRunEnded({
    required String journeyId,
    required DateTime departureTime,
  }) async {
    final user = _signedInUser();
    final database = await _db;
    await database.insert('ended_journey_runs', {
      'user_id': user.id,
      'journey_id': journeyId,
      'departure_time': departureTime.toIso8601String(),
      'ended_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearEndedJourneyRun(String journeyId) async {
    final user = _signedInUser();
    final database = await _db;
    await database.delete(
      'ended_journey_runs',
      where: 'user_id = ? AND journey_id = ?',
      whereArgs: [user.id, journeyId],
    );
  }

  static String journeyRunKey(String journeyId, DateTime departureTime) {
    return _journeyRunKey(journeyId, departureTime);
  }

  Future<void> recordSearch({
    required JourneyLocation origin,
    required JourneyLocation destination,
    DateTime? requestedTime,
    String? preference,
  }) async {
    final user = _signedInUser();
    final database = await _db;
    await database.transaction((database) async {
      final privacy = await database.query(
        'privacy_settings',
        where: 'user_id = ?',
        whereArgs: [user.id],
      );
      if (privacy.isNotEmpty && privacy.first['save_searches'] == 0) return;
      await database.delete(
        'recent_searches',
        where:
            'user_id = ? AND LOWER(TRIM(origin)) = ? AND LOWER(TRIM(destination)) = ?',
        whereArgs: [
          user.id,
          origin.name.trim().toLowerCase(),
          destination.name.trim().toLowerCase(),
        ],
      );
      await database.insert('recent_searches', {
        'user_id': user.id,
        'origin': origin.name.trim(),
        'destination': destination.name.trim(),
        'origin_latitude': origin.latitude,
        'origin_longitude': origin.longitude,
        'destination_latitude': destination.latitude,
        'destination_longitude': destination.longitude,
        'requested_time': requestedTime?.toIso8601String(),
        'preference': preference,
        'searched_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await database.rawDelete(
        '''
      DELETE FROM recent_searches WHERE user_id = ?
      AND id NOT IN (
        SELECT id FROM recent_searches WHERE user_id = ?
        ORDER BY searched_at DESC
        LIMIT 8
      )
    ''',
        [user.id, user.id],
      );
    });
  }

  Future<List<RecentSearch>> getRecentSearches({int limit = 5}) async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'recent_searches',
      where: 'user_id = ?',
      whereArgs: [user.id],
      orderBy: 'searched_at DESC',
      limit: limit,
    );
    return rows.map((row) {
      return RecentSearch(
        origin: row['origin'] as String,
        destination: row['destination'] as String,
        searchedAt: DateTime.parse(row['searched_at'] as String),
        originLatitude: (row['origin_latitude'] as num?)?.toDouble(),
        originLongitude: (row['origin_longitude'] as num?)?.toDouble(),
        destinationLatitude: (row['destination_latitude'] as num?)?.toDouble(),
        destinationLongitude: (row['destination_longitude'] as num?)
            ?.toDouble(),
        requestedTime: DateTime.tryParse(
          row['requested_time'] as String? ?? '',
        ),
        preference: row['preference'] as String?,
      );
    }).toList();
  }

  Future<List<FavouriteCategory>> getFavouriteCategories() async {
    final user = _signedInUser();
    final database = await _db;
    await _ensureDefaultFavouriteCategories(database, user.id);
    final rows = await database.query(
      'favourite_categories',
      where: 'user_id = ?',
      whereArgs: [user.id],
      orderBy: 'created_at ASC',
    );
    return rows.map((row) {
      return FavouriteCategory(
        id: row['id'] as String,
        name: row['name'] as String,
        colourValue: row['colour_value'] as int,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  Future<FavouriteCategory> addFavouriteCategory({
    required String name,
    required int colourValue,
  }) async {
    final user = _signedInUser();
    final database = await _db;
    final category = FavouriteCategory(
      id: 'category-${user.id}-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      colourValue: colourValue,
      createdAt: DateTime.now(),
    );
    await database.insert(
      'favourite_categories',
      _categoryToDatabaseMap(category, user.id),
    );
    return category;
  }

  Future<void> updateFavouriteCategory(FavouriteCategory category) async {
    final user = _signedInUser();
    final database = await _db;
    await database.update(
      'favourite_categories',
      _categoryToDatabaseMap(category, user.id),
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, category.id],
    );
  }

  Future<void> deleteFavouriteCategory(String categoryId) async {
    final user = _signedInUser();
    final database = await _db;
    final categories = await getFavouriteCategories();
    FavouriteCategory? fallback;
    for (final category in categories) {
      if (category.id != categoryId) {
        fallback = category;
        break;
      }
    }
    if (fallback == null) return;
    final fallbackCategory = fallback;

    await database.update(
      'favourites',
      {'category_id': fallbackCategory.id},
      where: 'user_id = ? AND category_id = ?',
      whereArgs: [user.id, categoryId],
    );
    await database.delete(
      'favourite_categories',
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, categoryId],
    );
  }

  Future<void> addFavourite(FavouriteItem favourite) async {
    final user = _signedInUser();
    final database = await _db;
    if (!const {'Route', 'Stop', 'Journey'}.contains(favourite.type)) {
      throw ArgumentError.value(
        favourite.type,
        'type',
        'Unsupported favourite',
      );
    }
    final category = await database.query(
      'favourite_categories',
      columns: ['id'],
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, favourite.categoryId],
      limit: 1,
    );
    if (category.isEmpty) {
      throw StateError('The selected favourite category no longer exists.');
    }
    await database.insert(
      'favourites',
      _favouriteToDatabaseMap(favourite, user.id),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateFavourite(FavouriteItem favourite) async {
    final user = _signedInUser();
    final database = await _db;
    await database.update(
      'favourites',
      _favouriteToDatabaseMap(favourite, user.id),
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, favourite.id],
    );
  }

  Future<void> deleteFavourite(String id) async {
    final user = _signedInUser();
    final database = await _db;
    await database.delete(
      'favourites',
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, id],
    );
  }

  Future<List<FavouriteItem>> getFavourites({String? categoryId}) async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'favourites',
      where: categoryId == null
          ? 'user_id = ?'
          : 'user_id = ? AND category_id = ?',
      whereArgs: categoryId == null ? [user.id] : [user.id, categoryId],
      orderBy: 'created_at DESC',
    );
    return rows.map((row) {
      return FavouriteItem(
        id: row['id'] as String,
        title: row['title'] as String,
        subtitle: row['subtitle'] as String,
        referenceId: row['reference_id'] as String,
        categoryId: row['category_id'] as String,
        type: row['type'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }

  Future<void> recordServiceUse(TransitRoute route) async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'service_usage',
      columns: ['usage_count'],
      where: 'user_id = ? AND route_id = ?',
      whereArgs: [user.id, route.id],
      limit: 1,
    );
    final previousCount = rows.isEmpty ? 0 : rows.first['usage_count'] as int;
    await database.insert('service_usage', {
      'user_id': user.id,
      'route_id': route.id,
      'route_number': route.number,
      'route_name': route.name,
      'mode': route.mode,
      'usage_count': previousCount + 1,
      'last_used_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ServiceUsage>> getFrequentServices({int limit = 4}) async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'service_usage',
      where: 'user_id = ?',
      whereArgs: [user.id],
      orderBy: 'usage_count DESC, last_used_at DESC',
      limit: limit,
    );
    return rows.map((row) {
      return ServiceUsage(
        routeId: row['route_id'] as String,
        routeNumber: row['route_number'] as String,
        routeName: row['route_name'] as String,
        mode: row['mode'] as String,
        usageCount: row['usage_count'] as int,
        lastUsedAt: DateTime.parse(row['last_used_at'] as String),
      );
    }).toList();
  }

  Map<String, Object?> _savedJourneyToDatabaseMap(
    SavedJourney journey,
    int userId,
  ) {
    return {
      'user_id': userId,
      'id': journey.id,
      'origin': journey.origin,
      'destination': journey.destination,
      'origin_latitude': journey.originLatitude,
      'origin_longitude': journey.originLongitude,
      'destination_latitude': journey.destinationLatitude,
      'destination_longitude': journey.destinationLongitude,
      'route_summary': journey.routeSummary,
      'departure_time': journey.departureTime.toIso8601String(),
      'duration_minutes': journey.durationMinutes,
      'fare': journey.fare,
      'known_fare': journey.knownFare,
      'route_ids': jsonEncode(journey.routeIds),
      'modes': jsonEncode(journey.modes),
      'preference': journey.preference,
      'depart_at': journey.departAt ? 1 : 0,
      'maximum_walking_metres': journey.maximumWalkingMetres,
      'accessible_only': journey.accessibleOnly ? 1 : 0,
      'fewer_transfers': journey.fewerTransfers ? 1 : 0,
      'walking_metres': journey.walkingMetres,
      'transfer_count': journey.transferCount,
      'saved_at': journey.savedAt.toIso8601String(),
    };
  }

  SavedJourney _savedJourneyFromDatabaseMap(Map<String, Object?> row) {
    return SavedJourney(
      id: row['id'] as String,
      origin: row['origin'] as String,
      destination: row['destination'] as String,
      routeSummary: row['route_summary'] as String,
      departureTime: DateTime.parse(row['departure_time'] as String),
      durationMinutes: row['duration_minutes'] as int,
      fare: (row['fare'] as num).toDouble(),
      savedAt: DateTime.parse(row['saved_at'] as String),
      originLatitude: (row['origin_latitude'] as num?)?.toDouble(),
      originLongitude: (row['origin_longitude'] as num?)?.toDouble(),
      destinationLatitude: (row['destination_latitude'] as num?)?.toDouble(),
      destinationLongitude: (row['destination_longitude'] as num?)?.toDouble(),
      routeIds: _decodeStringList(row['route_ids']),
      modes: _decodeStringList(row['modes']),
      preference: row['preference'] as String? ?? 'Recommended',
      departAt: (row['depart_at'] as int? ?? 1) == 1,
      maximumWalkingMetres: row['maximum_walking_metres'] as int? ?? 2000,
      accessibleOnly: (row['accessible_only'] as int? ?? 0) == 1,
      fewerTransfers: (row['fewer_transfers'] as int? ?? 0) == 1,
      walkingMetres: row['walking_metres'] as int? ?? 0,
      transferCount: row['transfer_count'] as int? ?? 0,
      knownFare: (row['known_fare'] as num?)?.toDouble(),
    );
  }

  Map<String, Object?> _categoryToDatabaseMap(
    FavouriteCategory category,
    int userId,
  ) {
    return {
      'user_id': userId,
      'id': category.id,
      'name': category.name,
      'colour_value': category.colourValue,
      'created_at': category.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _favouriteToDatabaseMap(
    FavouriteItem favourite,
    int userId,
  ) {
    return {
      'user_id': userId,
      'id': favourite.id,
      'title': favourite.title,
      'subtitle': favourite.subtitle,
      'type': favourite.type,
      'reference_id': favourite.referenceId,
      'category_id': favourite.categoryId,
      'created_at': favourite.createdAt.toIso8601String(),
    };
  }

  Future<void> _ensureDefaultFavouriteCategories(
    Database database,
    int userId,
  ) async {
    final existing = await database.query(
      'favourite_categories',
      columns: ['id'],
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    final now = DateTime.now();
    await database.insert('favourite_categories', {
      'user_id': userId,
      'id': 'category-personal-$userId',
      'name': 'Personal',
      'colour_value': 0xFF1565C0,
      'created_at': now.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await database.insert('favourite_categories', {
      'user_id': userId,
      'id': 'category-daily-$userId',
      'name': 'Daily Travel',
      'colour_value': 0xFF00897B,
      'created_at': now.add(const Duration(microseconds: 1)).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  List<String> _decodeStringList(Object? value) {
    if (value is! String || value.isEmpty) return const [];
    try {
      return (jsonDecode(value) as List<dynamic>).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  // Record a completed journey
  Future<void> recordCompletedJourney(JourneyOption journey) async {
    final user = _signedInUser();
    final database = await _db;
    final completedAt = DateTime.now();

    final journeyId = 'completed-${completedAt.microsecondsSinceEpoch}';

    await database.transaction((transaction) async {
      await transaction.insert('completed_journeys', {
        'user_id': user.id,
        'id': journeyId,
        'origin': journey.origin.name,
        'destination': journey.destination.name,
        'route_summary': journey.routeSummary,
        'completed_at': completedAt.toIso8601String(),
        'duration_minutes': journey.totalDurationMinutes,
        'fare': journey.totalFare,
        'walking_metres': journey.walkingMetres,
      });

      for (var index = 0; index < journey.legs.length; index++) {
        final leg = journey.legs[index];

        await transaction.insert('completed_journey_legs', {
          'user_id': user.id,
          'journey_id': journeyId,
          'leg_order': index,
          'route_number': leg.route.number,
          'mode': leg.route.mode,
          'from_stop_name': leg.from.name,
          'to_stop_name': leg.to.name,
        });
      }
    });
  }

  // Get completed journeys
  Future<List<CompletedJourney>> getCompletedJourneys({
    DateTime? start,
    DateTime? end,
  }) async {
    final user = _signedInUser();
    final database = await _db;

    final conditions = <String>['user_id = ?'];
    final arguments = <Object?>[user.id];

    if (start != null) {
      conditions.add('completed_at >= ?');
      arguments.add(start.toIso8601String());
    }

    if (end != null) {
      conditions.add('completed_at < ?');
      arguments.add(end.toIso8601String());
    }

    final journeyRows = await database.query(
      'completed_journeys',
      where: conditions.join(' AND '),
      whereArgs: arguments,
      orderBy: 'completed_at DESC',
    );

    final journeys = <CompletedJourney>[];

    for (final journeyRow in journeyRows) {
      final journeyId = journeyRow['id'] as String;

      final legRows = await database.query(
        'completed_journey_legs',
        where: 'user_id = ? AND journey_id = ?',
        whereArgs: [user.id, journeyId],
        orderBy: 'leg_order ASC',
      );

      final legs = legRows.map((legRow) {
        return CompletedJourneyLeg(
          routeNumber: legRow['route_number'] as String,
          mode: legRow['mode'] as String,
          fromStopName: legRow['from_stop_name'] as String,
          toStopName: legRow['to_stop_name'] as String,
        );
      }).toList();

      journeys.add(
        CompletedJourney(
          id: journeyId,
          origin: journeyRow['origin'] as String,
          destination: journeyRow['destination'] as String,
          routeSummary: journeyRow['route_summary'] as String,
          completedAt: DateTime.parse(journeyRow['completed_at'] as String),
          durationMinutes: journeyRow['duration_minutes'] as int,
          fare: (journeyRow['fare'] as num).toDouble(),
          walkingMetres: journeyRow['walking_metres'] as int? ?? 0,
          legs: legs,
        ),
      );
    }

    return journeys;
  }

  // Convert a date into a monthly database key
  String _monthKey(DateTime month) {
    final monthNumber = month.month.toString().padLeft(2, '0');

    return '${month.year}-$monthNumber';
  }

  // Get the monthly transport budget
  Future<double?> getMonthlyTravelBudget(DateTime month) async {
    final user = _signedInUser();
    final database = await _db;

    final rows = await database.query(
      'monthly_travel_budgets',
      where: 'user_id = ? AND month_key = ?',
      whereArgs: [user.id, _monthKey(month)],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return (rows.first['amount'] as num).toDouble();
  }

  // Save or update the monthly transport budget
  Future<void> setMonthlyTravelBudget({
    required DateTime month,
    required double amount,
  }) async {
    final user = _signedInUser();
    final database = await _db;

    await database.insert('monthly_travel_budgets', {
      'user_id': user.id,
      'month_key': _monthKey(month),
      'amount': amount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Delete a completed journey
  Future<void> deleteCompletedJourney(String journeyId) async {
    final user = _signedInUser();
    final database = await _db;

    await database.transaction((transaction) async {
      await transaction.delete(
        'completed_journey_legs',
        where: 'user_id = ? AND journey_id = ?',
        whereArgs: [user.id, journeyId],
      );

      await transaction.delete(
        'completed_journeys',
        where: 'user_id = ? AND id = ?',
        whereArgs: [user.id, journeyId],
      );
    });
  }

  String _hashPassword(String password) {
    final passwordBytes = utf8.encode(password);
    return sha256.convert(passwordBytes).toString();
  }

  Future<bool> emailExists(String email) async {
    final database = await _db;
    final normalisedEmail = email.trim().toLowerCase();

    final rows = await database.query(
      'users',
      columns: ['id'],
      where: 'email = ?',
      whereArgs: [normalisedEmail],
      limit: 1,
    );

    return rows.isNotEmpty;
  }

  Future<void> registerUser({
    required String fullName,
    required String email,
    required String phone,
    required String password,
  }) async {
    final validation = validateNewPassword(password);
    if (validation != null) throw ArgumentError(validation);
    final database = await _db;

    final normalisedEmail = email.trim().toLowerCase();
    await database.transaction((transaction) async {
      await transaction.insert('users', {
        'full_name': fullName.trim(),
        'email': normalisedEmail,
        'phone': phone.trim(),
        'password_hash': _hashPassword(password),
        'created_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await transaction.delete(
        'login_attempts',
        where: 'email = ?',
        whereArgs: [normalisedEmail],
      );
    });
  }

  Future<AppUser?> loginUser({
    required String email,
    required String password,
  }) async {
    _currentUser.value = null;
    final database = await _db;
    final normalisedEmail = email.trim().toLowerCase();
    final now = (_nowForTesting?.call() ?? DateTime.now()).toUtc();
    final result = await database.transaction<({AppUser? user, String? error})>((
      transaction,
    ) async {
      final attempts = await transaction.query(
        'login_attempts',
        where: 'email = ?',
        whereArgs: [normalisedEmail],
        limit: 1,
      );
      final previous = attempts.isEmpty ? null : attempts.first;
      final lockedUntil = DateTime.tryParse(
        previous?['locked_until'] as String? ?? '',
      )?.toUtc();
      if (lockedUntil != null && lockedUntil.isAfter(now)) {
        return (user: null, error: _loginLockMessage(now, lockedUntil));
      }

      final rows = await transaction.query(
        'users',
        where: 'email = ?',
        whereArgs: [normalisedEmail],
        limit: 1,
      );
      final passwordMatches =
          rows.isNotEmpty &&
          rows.first['password_hash'] == _hashPassword(password);
      if (!passwordMatches) {
        final previousFailures =
            lockedUntil != null && !lockedUntil.isAfter(now)
            ? 0
            : (previous?['failed_attempts'] as int? ?? 0);
        final failures = previousFailures + 1;
        final newLockedUntil = failures >= _maximumLoginFailures
            ? now.add(_loginLockDuration)
            : null;
        await transaction.insert('login_attempts', {
          'email': normalisedEmail,
          'failed_attempts': failures,
          'locked_until': newLockedUntil?.toIso8601String(),
          'last_failed_at': now.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        if (newLockedUntil != null) {
          return (user: null, error: _loginLockMessage(now, newLockedUntil));
        }
        final remaining = _maximumLoginFailures - failures;
        return (
          user: null,
          error:
              'Incorrect email address or password. $remaining ${remaining == 1 ? 'attempt' : 'attempts'} remaining.',
        );
      }

      await transaction.delete(
        'login_attempts',
        where: 'email = ?',
        whereArgs: [normalisedEmail],
      );
      return (user: AppUser.fromMap(rows.first), error: null);
    });
    if (result.error != null) {
      throw LoginAttemptException(result.error!);
    }
    final user = result.user!;
    _currentUser.value = user;
    return user;
  }

  String _loginLockMessage(DateTime now, DateTime lockedUntil) {
    final minutes = (lockedUntil.difference(now).inSeconds / 60).ceil().clamp(
      1,
      _loginLockDuration.inMinutes,
    );
    return 'Too many incorrect login attempts. Try again in $minutes ${minutes == 1 ? 'minute' : 'minutes'}, or reset your password.';
  }

  AppUser _signedInUser() {
    final user = _currentUser.value;
    if (user == null) {
      throw const AccountSettingsException(
        'Please log in again to manage your account.',
      );
    }
    return user;
  }

  Future<Map<String, Object?>> _verifyCurrentPassword(
    Transaction transaction,
    int userId,
    String password,
  ) async {
    final rows = await transaction.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty ||
        rows.first['password_hash'] != _hashPassword(password)) {
      throw const AccountSettingsException(
        'Your current password is incorrect.',
      );
    }
    return rows.first;
  }

  @override
  Future<void> updateProfile({
    required String fullName,
    required String email,
    required String phone,
  }) async {
    final user = _signedInUser();
    final error =
        validateProfileName(fullName) ??
        validateProfileEmail(email) ??
        validateProfilePhone(phone);
    if (error != null) throw AccountSettingsException(error);
    final normalizedEmail = email.trim().toLowerCase();
    final database = await _db;
    final updated = await database.transaction((transaction) async {
      final rows = await transaction.query(
        'users',
        where: 'id = ?',
        whereArgs: [user.id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const AccountSettingsException(
          'Please log in again to manage your account.',
        );
      }
      final row = rows.first;
      final duplicates = await transaction.query(
        'users',
        columns: ['id'],
        where: 'email = ? AND id != ?',
        whereArgs: [normalizedEmail, user.id],
        limit: 1,
      );
      if (duplicates.isNotEmpty) {
        throw const AccountSettingsException(
          'This email is already used by another account.',
        );
      }
      final changes = <String, Object?>{
        'full_name': fullName.trim(),
        'email': normalizedEmail,
        'phone': phone.trim(),
      };
      await transaction.update(
        'users',
        changes,
        where: 'id = ?',
        whereArgs: [user.id],
      );
      return AppUser.fromMap({...row, ...changes});
    });
    if (_currentUser.value?.id == user.id) _currentUser.value = updated;
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _signedInUser();
    final error = validateNewPassword(newPassword);
    if (error != null) throw AccountSettingsException(error);
    if (newPassword == currentPassword) {
      throw const AccountSettingsException(
        'Choose a password different from your current password.',
      );
    }
    final database = await _db;
    await database.transaction((transaction) async {
      await _verifyCurrentPassword(transaction, user.id, currentPassword);
      await transaction.update(
        'users',
        {'password_hash': _hashPassword(newPassword)},
        where: 'id = ?',
        whereArgs: [user.id],
      );
    });
  }

  static Future<void> _createPrivacySettingsTable(Database database) async {
    await database.execute(
      'CREATE TABLE IF NOT EXISTS privacy_settings('
      'id INTEGER PRIMARY KEY CHECK(id = 1), save_searches INTEGER NOT NULL DEFAULT 1)',
    );
  }

  static Future<void> _createTravelSettingsTables(Database database) async {
    await database.execute('''CREATE TABLE IF NOT EXISTS travel_preferences(
      user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      transport_modes TEXT NOT NULL, maximum_walking_metres INTEGER NOT NULL,
      prefer_lowest_fare INTEGER NOT NULL, prefer_fewer_transfers INTEGER NOT NULL,
      travel_notifications INTEGER NOT NULL)''');
    await database.execute(
      '''CREATE TABLE IF NOT EXISTS saved_places(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      label TEXT NOT NULL COLLATE NOCASE, location_name TEXT NOT NULL,
      latitude REAL NOT NULL, longitude REAL NOT NULL, UNIQUE(user_id, label))''',
    );
  }

  @override
  Future<TravelPreferences> getTravelPreferences() async {
    final user = _currentUser.value;
    if (user == null) return const TravelPreferences();
    final database = await _db;
    final rows = await database.query(
      'travel_preferences',
      where: 'user_id = ?',
      whereArgs: [user.id],
    );
    return rows.isEmpty
        ? const TravelPreferences()
        : TravelPreferences.fromMap(rows.first);
  }

  @override
  Future<void> saveTravelPreferences(TravelPreferences preferences) async {
    final user = _signedInUser();
    if (preferences.transportModes.isEmpty ||
        !const {
          'Bus',
          'Train',
          'Ferry',
        }.containsAll(preferences.transportModes) ||
        preferences.maximumWalkingMetres < 500 ||
        preferences.maximumWalkingMetres > 5000) {
      throw const AccountSettingsException(
        'Select at least one transport mode and a walking distance between 0.5 and 5 km.',
      );
    }
    final database = await _db;
    await database.insert('travel_preferences', {
      'user_id': user.id,
      ...preferences.toMap(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<SavedPlace>> getSavedPlaces() async {
    final user = _currentUser.value;
    if (user == null) return [];
    final database = await _db;
    final rows = await database.query(
      'saved_places',
      where: 'user_id = ?',
      whereArgs: [user.id],
      orderBy: 'label COLLATE NOCASE',
    );
    return rows.map(SavedPlace.fromMap).toList();
  }

  @override
  Future<void> savePlace({
    int? id,
    required String label,
    required JourneyLocation location,
  }) async {
    final user = _signedInUser();
    if (label.trim().isEmpty ||
        label.trim().length > 50 ||
        location.name.trim().isEmpty ||
        !location.latitude.isFinite ||
        !location.longitude.isFinite ||
        !LocationService.isInsideMalaysia(
          location.latitude,
          location.longitude,
        )) {
      throw const AccountSettingsException(
        'Enter a place name of up to 50 characters and select a location in Malaysia.',
      );
    }
    final database = await _db;
    await database.transaction((transaction) async {
      final duplicates = await transaction.query(
        'saved_places',
        columns: ['id'],
        where: 'user_id = ? AND label = ? AND id != ?',
        whereArgs: [user.id, label.trim(), id ?? -1],
      );
      if (duplicates.isNotEmpty) {
        throw const AccountSettingsException(
          'You already have a saved place with this name.',
        );
      }
      final values = <String, Object?>{
        'label': label.trim(),
        'location_name': location.name.trim(),
        'latitude': location.latitude,
        'longitude': location.longitude,
      };
      if (id == null) {
        await transaction.insert('saved_places', {
          'user_id': user.id,
          ...values,
        });
      } else {
        final count = await transaction.update(
          'saved_places',
          values,
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, user.id],
        );
        if (count != 1) {
          throw const AccountSettingsException(
            'This saved place is no longer available.',
          );
        }
      }
    });
  }

  @override
  Future<void> deletePlace(int id) async {
    final user = _signedInUser();
    final database = await _db;
    await database.delete(
      'saved_places',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, user.id],
    );
  }

  @override
  Future<bool> getSearchHistoryEnabled() async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'privacy_settings',
      where: 'user_id = ?',
      whereArgs: [user.id],
    );
    return rows.isEmpty || rows.first['save_searches'] == 1;
  }

  @override
  Future<void> setSearchHistoryEnabled(bool enabled) async {
    final user = _signedInUser();
    final database = await _db;
    await database.insert('privacy_settings', {
      'user_id': user.id,
      'save_searches': enabled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> clearRecentSearches() async {
    final user = _signedInUser();
    final database = await _db;
    await database.delete(
      'recent_searches',
      where: 'user_id = ?',
      whereArgs: [user.id],
    );
  }

  /// Called by PasswordRecoveryService only after server-side email verification.
  Future<void> updateRecoveredPassword(String email, String password) async {
    final validation = validateNewPassword(password);
    if (validation != null) throw ArgumentError(validation);
    final database = await _db;
    final normalisedEmail = email.trim().toLowerCase();
    await database.transaction((transaction) async {
      final count = await transaction.update(
        'users',
        {'password_hash': _hashPassword(password)},
        where: 'email = ?',
        whereArgs: [normalisedEmail],
      );
      if (count != 1) {
        throw StateError('The account is no longer available on this device.');
      }
      await transaction.delete(
        'login_attempts',
        where: 'email = ?',
        whereArgs: [normalisedEmail],
      );
    });
  }

  Future<AccessibilityPreferences> getAccessibilityPreferences() async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'accessibility_preferences',
      where: 'user_id = ?',
      whereArgs: [user.id],
      limit: 1,
    );
    if (rows.isEmpty) return AccessibilityPreferences.defaults;
    final row = rows.first;
    return AccessibilityPreferences(
      selectedNeeds: _decodeStringList(row['selected_needs']).toSet(),
      accessibleRoutesOnly: (row['accessible_routes_only'] as int? ?? 1) == 1,
      workingLiftsOnly: (row['working_lifts_only'] as int? ?? 1) == 1,
      audioGuidance: (row['audio_guidance'] as int? ?? 0) == 1,
      visualAlerts: (row['visual_alerts'] as int? ?? 1) == 1,
    );
  }

  Future<void> saveAccessibilityPreferences(
    AccessibilityPreferences preferences,
  ) async {
    final user = _signedInUser();
    final database = await _db;
    await database.insert('accessibility_preferences', {
      'user_id': user.id,
      'selected_needs': jsonEncode(preferences.selectedNeeds.toList()),
      'accessible_routes_only': preferences.accessibleRoutesOnly ? 1 : 0,
      'working_lifts_only': preferences.workingLiftsOnly ? 1 : 0,
      'audio_guidance': preferences.audioGuidance ? 1 : 0,
      'visual_alerts': preferences.visualAlerts ? 1 : 0,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<AccessibilityObservation>> getAccessibilityObservations({
    String? stopId,
  }) async {
    final user = _signedInUser();
    final database = await _db;
    final rows = await database.query(
      'accessibility_observations',
      where: stopId == null ? 'user_id = ?' : 'user_id = ? AND stop_id = ?',
      whereArgs: stopId == null ? [user.id] : [user.id, stopId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_accessibilityObservationFromMap).toList();
  }

  Future<void> saveAccessibilityObservation(
    AccessibilityObservation observation,
  ) async {
    final user = _signedInUser();
    final database = await _db;
    await database.insert('accessibility_observations', {
      'user_id': user.id,
      'id': observation.id,
      'stop_id': observation.stopId,
      'stop_name': observation.stopName,
      'facility': observation.facility.name,
      'status': observation.status.name,
      'note': observation.note.trim(),
      'created_at': observation.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteAccessibilityObservation(String id) async {
    final user = _signedInUser();
    final database = await _db;
    await database.delete(
      'accessibility_observations',
      where: 'user_id = ? AND id = ?',
      whereArgs: [user.id, id],
    );
  }

  AccessibilityObservation _accessibilityObservationFromMap(
    Map<String, Object?> row,
  ) {
    return AccessibilityObservation(
      id: row['id'] as String,
      stopId: row['stop_id'] as String,
      stopName: row['stop_name'] as String,
      facility: AccessibilityFacility.values.firstWhere(
        (value) => value.name == row['facility'],
        orElse: () => AccessibilityFacility.wheelchairAccess,
      ),
      status: AccessibilityFacilityStatus.values.firstWhere(
        (value) => value.name == row['status'],
        orElse: () => AccessibilityFacilityStatus.unknown,
      ),
      note: row['note'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

Future<void> _createUserScopedDataTables(Database database) async {
  await database.execute('''CREATE TABLE favourite_categories(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL, name TEXT NOT NULL, colour_value INTEGER NOT NULL,
    created_at TEXT NOT NULL, PRIMARY KEY(user_id, id))''');
  await database.execute('''CREATE TABLE saved_journeys(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL, origin TEXT NOT NULL, destination TEXT NOT NULL,
    origin_latitude REAL, origin_longitude REAL, destination_latitude REAL,
    destination_longitude REAL, route_summary TEXT NOT NULL,
    departure_time TEXT NOT NULL, duration_minutes INTEGER NOT NULL,
    fare REAL NOT NULL, known_fare REAL, route_ids TEXT NOT NULL DEFAULT '[]',
    modes TEXT NOT NULL DEFAULT '[]', preference TEXT NOT NULL DEFAULT 'Recommended',
    depart_at INTEGER NOT NULL DEFAULT 1,
    maximum_walking_metres INTEGER NOT NULL DEFAULT 2000,
    accessible_only INTEGER NOT NULL DEFAULT 0,
    fewer_transfers INTEGER NOT NULL DEFAULT 0,
    walking_metres INTEGER NOT NULL DEFAULT 0,
    transfer_count INTEGER NOT NULL DEFAULT 0, saved_at TEXT NOT NULL,
    PRIMARY KEY(user_id, id))''');
  await database.execute('''CREATE TABLE favourites(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL,
    type TEXT NOT NULL, reference_id TEXT NOT NULL, category_id TEXT NOT NULL,
    created_at TEXT NOT NULL, PRIMARY KEY(user_id, id),
    FOREIGN KEY(user_id, category_id)
      REFERENCES favourite_categories(user_id, id))''');
  await database.execute(
    'CREATE UNIQUE INDEX favourites_reference_unique '
    'ON favourites(user_id, type, reference_id)',
  );
  await database.execute('''CREATE TABLE recent_searches(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    origin TEXT NOT NULL, destination TEXT NOT NULL, origin_latitude REAL,
    origin_longitude REAL, destination_latitude REAL, destination_longitude REAL,
    requested_time TEXT, preference TEXT, searched_at TEXT NOT NULL,
    UNIQUE(user_id, origin, destination))''');
  await database.execute('''CREATE TABLE ended_journey_runs(
    user_id INTEGER NOT NULL, journey_id TEXT NOT NULL,
    departure_time TEXT NOT NULL, ended_at TEXT NOT NULL,
    PRIMARY KEY(user_id, journey_id),
    FOREIGN KEY(user_id, journey_id)
      REFERENCES saved_journeys(user_id, id) ON DELETE CASCADE)''');
  await database.execute('''CREATE TABLE service_usage(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    route_id TEXT NOT NULL, route_number TEXT NOT NULL, route_name TEXT NOT NULL,
    mode TEXT NOT NULL, usage_count INTEGER NOT NULL, last_used_at TEXT NOT NULL,
    PRIMARY KEY(user_id, route_id))''');
  await database.execute('''CREATE TABLE completed_journeys(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL, origin TEXT NOT NULL, destination TEXT NOT NULL,
    route_summary TEXT NOT NULL, completed_at TEXT NOT NULL,
    duration_minutes INTEGER NOT NULL, fare REAL NOT NULL,
    walking_metres INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(user_id, id))''');
  await database.execute('''CREATE TABLE completed_journey_legs(
    id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL,
    journey_id TEXT NOT NULL, leg_order INTEGER NOT NULL,
    route_number TEXT NOT NULL, mode TEXT NOT NULL,
    from_stop_name TEXT NOT NULL, to_stop_name TEXT NOT NULL,
    FOREIGN KEY(user_id, journey_id)
      REFERENCES completed_journeys(user_id, id) ON DELETE CASCADE)''');
  await database.execute('''CREATE TABLE monthly_travel_budgets(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    month_key TEXT NOT NULL, amount REAL NOT NULL,
    PRIMARY KEY(user_id, month_key))''');
  await database.execute('''CREATE TABLE privacy_settings(
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    save_searches INTEGER NOT NULL DEFAULT 1)''');
  await database.execute('''CREATE TABLE accessibility_preferences(
    user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    selected_needs TEXT NOT NULL, accessible_routes_only INTEGER NOT NULL,
    working_lifts_only INTEGER NOT NULL, audio_guidance INTEGER NOT NULL,
    visual_alerts INTEGER NOT NULL, updated_at TEXT NOT NULL)''');
  await database.execute('''CREATE TABLE accessibility_observations(
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL, stop_id TEXT NOT NULL, stop_name TEXT NOT NULL,
    facility TEXT NOT NULL, status TEXT NOT NULL, note TEXT NOT NULL,
    created_at TEXT NOT NULL, PRIMARY KEY(user_id, id))''');
  await database.execute(
    'CREATE INDEX accessibility_observations_stop_index '
    'ON accessibility_observations(user_id, stop_id, created_at DESC)',
  );
}

Future<void> _createLoginAttemptsTable(Database database) async {
  await database.execute('''CREATE TABLE IF NOT EXISTS login_attempts(
    email TEXT PRIMARY KEY COLLATE NOCASE,
    failed_attempts INTEGER NOT NULL,
    locked_until TEXT,
    last_failed_at TEXT NOT NULL)''');
}

Future<void> _migratePersonalDataToUsers(Database database) async {
  await _createLegacyAccessibilityTablesIfMissing(database);
  const tables = [
    'completed_journey_legs',
    'ended_journey_runs',
    'favourites',
    'favourite_categories',
    'saved_journeys',
    'recent_searches',
    'service_usage',
    'completed_journeys',
    'monthly_travel_budgets',
    'privacy_settings',
    'accessibility_preferences',
    'accessibility_observations',
  ];
  for (final table in tables) {
    await database.execute('ALTER TABLE $table RENAME TO ${table}_legacy');
  }
  await database.execute('DROP INDEX IF EXISTS favourites_reference_unique');
  await database.execute(
    'DROP INDEX IF EXISTS accessibility_observations_stop_index',
  );
  await _createUserScopedDataTables(database);

  final users = await database.query(
    'users',
    columns: ['id'],
    orderBy: 'created_at ASC, id ASC',
    limit: 1,
  );
  if (users.isNotEmpty) {
    final owner = users.first['id'];
    await database.execute(
      '''INSERT INTO favourite_categories
      SELECT ?, id, name, colour_value, created_at
      FROM favourite_categories_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO saved_journeys
      SELECT ?, id, origin, destination, origin_latitude, origin_longitude,
        destination_latitude, destination_longitude, route_summary,
        departure_time, duration_minutes, fare, known_fare, route_ids, modes,
        preference, depart_at, maximum_walking_metres, accessible_only,
        fewer_transfers, walking_metres, transfer_count, saved_at
      FROM saved_journeys_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO favourites
      SELECT ?, id, title, subtitle, type, reference_id, category_id, created_at
      FROM favourites_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO recent_searches
      (user_id, origin, destination, origin_latitude, origin_longitude,
       destination_latitude, destination_longitude, requested_time, preference,
       searched_at)
      SELECT ?, origin, destination, origin_latitude, origin_longitude,
       destination_latitude, destination_longitude, requested_time, preference,
       searched_at FROM recent_searches_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO ended_journey_runs
      SELECT ?, journey_id, departure_time, ended_at
      FROM ended_journey_runs_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO service_usage
      SELECT ?, route_id, route_number, route_name, mode, usage_count, last_used_at
      FROM service_usage_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO completed_journeys
      SELECT ?, id, origin, destination, route_summary, completed_at,
        duration_minutes, fare, walking_metres FROM completed_journeys_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO completed_journey_legs
      (user_id, journey_id, leg_order, route_number, mode, from_stop_name,
       to_stop_name)
      SELECT ?, journey_id, leg_order, route_number, mode, from_stop_name,
       to_stop_name FROM completed_journey_legs_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO monthly_travel_budgets
      SELECT ?, month_key, amount FROM monthly_travel_budgets_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO privacy_settings
      SELECT ?, save_searches FROM privacy_settings_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO accessibility_preferences
      SELECT ?, selected_needs, accessible_routes_only, working_lifts_only,
        audio_guidance, visual_alerts, updated_at
      FROM accessibility_preferences_legacy''',
      [owner],
    );
    await database.execute(
      '''INSERT INTO accessibility_observations
      SELECT ?, id, stop_id, stop_name, facility, status, note, created_at
      FROM accessibility_observations_legacy''',
      [owner],
    );
  }

  for (final table in tables) {
    await database.execute('DROP TABLE ${table}_legacy');
  }
}

Future<void> _createLegacyAccessibilityTablesIfMissing(
  Database database,
) async {
  await database.execute(
    '''CREATE TABLE IF NOT EXISTS accessibility_preferences(
    id INTEGER PRIMARY KEY CHECK(id = 1), selected_needs TEXT NOT NULL,
    accessible_routes_only INTEGER NOT NULL, working_lifts_only INTEGER NOT NULL,
    audio_guidance INTEGER NOT NULL, visual_alerts INTEGER NOT NULL,
    updated_at TEXT NOT NULL)''',
  );
  await database.execute(
    '''CREATE TABLE IF NOT EXISTS accessibility_observations(
    id TEXT PRIMARY KEY, stop_id TEXT NOT NULL, stop_name TEXT NOT NULL,
    facility TEXT NOT NULL, status TEXT NOT NULL, note TEXT NOT NULL,
    created_at TEXT NOT NULL)''',
  );
  await database.execute(
    'CREATE INDEX IF NOT EXISTS accessibility_observations_stop_index '
    'ON accessibility_observations(stop_id, created_at DESC)',
  );
}

Future<void> _createEndedJourneyRunsTable(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS ended_journey_runs(
      journey_id TEXT PRIMARY KEY,
      departure_time TEXT NOT NULL,
      ended_at TEXT NOT NULL,
      FOREIGN KEY(journey_id) REFERENCES saved_journeys(id) ON DELETE CASCADE
    )
  ''');
}

String _journeyRunKey(String journeyId, DateTime departureTime) {
  return '$journeyId|${departureTime.toIso8601String()}';
}
