import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:crypto/crypto.dart';
import '../models/accessibility_models.dart';
import '../models/transit_models.dart';
import '../models/travel_history_models.dart';
import '../models/user_models.dart';

class LocalStorageService {
  LocalStorageService._();

  static final LocalStorageService instance = LocalStorageService._();

  Database? _database;

  Future<void> initialise() async {
    if (_database != null) return;

    final databasePath = path.join(
      await getDatabasesPath(),
      'smart_public_transport.db',
    );

    _database = await openDatabase(
      databasePath,
      version: 8,
      onConfigure: (database) async {
        await database.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE favourite_categories(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            colour_value INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE favourites(
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            type TEXT NOT NULL,
            reference_id TEXT NOT NULL,
            category_id TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(category_id) REFERENCES favourite_categories(id)
          )
        ''');
        await database.execute('''
          CREATE TABLE saved_journeys(
            id TEXT PRIMARY KEY,
            origin TEXT NOT NULL,
            destination TEXT NOT NULL,
            origin_latitude REAL,
            origin_longitude REAL,
            destination_latitude REAL,
            destination_longitude REAL,
            route_summary TEXT NOT NULL,
            departure_time TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            fare REAL NOT NULL,
            known_fare REAL,
            route_ids TEXT NOT NULL DEFAULT '[]',
            modes TEXT NOT NULL DEFAULT '[]',
            preference TEXT NOT NULL DEFAULT 'Recommended',
            depart_at INTEGER NOT NULL DEFAULT 1,
            maximum_walking_metres INTEGER NOT NULL DEFAULT 2000,
            accessible_only INTEGER NOT NULL DEFAULT 0,
            fewer_transfers INTEGER NOT NULL DEFAULT 0,
            walking_metres INTEGER NOT NULL DEFAULT 0,
            transfer_count INTEGER NOT NULL DEFAULT 0,
            saved_at TEXT NOT NULL
          )
        ''');
        await database.execute('''
          CREATE TABLE recent_searches(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            origin TEXT NOT NULL,
            destination TEXT NOT NULL,
            origin_latitude REAL,
            origin_longitude REAL,
            destination_latitude REAL,
            destination_longitude REAL,
            requested_time TEXT,
            preference TEXT,
            searched_at TEXT NOT NULL,
            UNIQUE(origin, destination)
          )
        ''');
        await database.execute('''
          CREATE TABLE service_usage(
            route_id TEXT PRIMARY KEY,
            route_number TEXT NOT NULL,
            route_name TEXT NOT NULL,
            mode TEXT NOT NULL,
            usage_count INTEGER NOT NULL,
            last_used_at TEXT NOT NULL
          )
        ''');
        await database.execute(
          'CREATE UNIQUE INDEX favourites_reference_unique '
              'ON favourites(type, reference_id)',
        );
        final now = DateTime.now();
        await database.insert('favourite_categories', {
          'id': 'category-personal',
          'name': 'Personal',
          'colour_value': 0xFF1565C0,
          'created_at': now.toIso8601String(),
        });
        await database.insert('favourite_categories', {
          'id': 'category-daily',
          'name': 'Daily Travel',
          'colour_value': 0xFF00897B,
          'created_at': now
              .add(const Duration(microseconds: 1))
              .toIso8601String(),
        });
        // Completed journey table
        await database.execute('''
          CREATE TABLE completed_journeys(
          id TEXT PRIMARY KEY,
          origin TEXT NOT NULL,
          destination TEXT NOT NULL,
          route_summary TEXT NOT NULL,
          completed_at TEXT NOT NULL,
          duration_minutes INTEGER NOT NULL,
          fare REAL NOT NULL,
          walking_metres INTEGER NOT NULL DEFAULT 0
        )
      ''');
        // Completed journey transport legs
        await database.execute('''
          CREATE TABLE completed_journey_legs(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          journey_id TEXT NOT NULL,
          leg_order INTEGER NOT NULL,
          route_number TEXT NOT NULL,
          mode TEXT NOT NULL,
          from_stop_name TEXT NOT NULL,
          to_stop_name TEXT NOT NULL,
          FOREIGN KEY(journey_id)
          REFERENCES completed_journeys(id)
          ON DELETE CASCADE
        )
      ''');

        // Monthly transport budget
        await database.execute('''
          CREATE TABLE monthly_travel_budgets(
          month_key TEXT PRIMARY KEY,
          amount REAL NOT NULL
        )
      ''');
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
        await _createAccessibilityTables(database);
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
    final database = await _db;
    await database.insert(
      'saved_journeys',
      _savedJourneyToDatabaseMap(journey),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isJourneySaved(String id) async {
    final database = await _db;
    final result = await database.query(
      'saved_journeys',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<SavedJourney>> getSavedJourneys() async {
    final database = await _db;
    final rows = await database.query(
      'saved_journeys',
      orderBy: 'saved_at DESC',
    );
    return rows.map(_savedJourneyFromDatabaseMap).toList();
  }

  Future<void> deleteSavedJourney(String id) async {
    final database = await _db;
    await database.transaction((transaction) async {
      await transaction.delete(
        'favourites',
        where: 'type = ? AND reference_id = ?',
        whereArgs: ['Journey', id],
      );
      await transaction.delete(
        'saved_journeys',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> recordSearch({
    required JourneyLocation origin,
    required JourneyLocation destination,
    DateTime? requestedTime,
    String? preference,
  }) async {
    final database = await _db;
    await database.delete(
      'recent_searches',
      where: 'LOWER(TRIM(origin)) = ? AND LOWER(TRIM(destination)) = ?',
      whereArgs: [
        origin.name.trim().toLowerCase(),
        destination.name.trim().toLowerCase(),
      ],
    );
    await database.insert('recent_searches', {
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
    await database.rawDelete('''
      DELETE FROM recent_searches
      WHERE id NOT IN (
        SELECT id FROM recent_searches
        ORDER BY searched_at DESC
        LIMIT 8
      )
    ''');
  }

  Future<List<RecentSearch>> getRecentSearches({int limit = 5}) async {
    final database = await _db;
    final rows = await database.query(
      'recent_searches',
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
    final database = await _db;
    final rows = await database.query(
      'favourite_categories',
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
    final database = await _db;
    final category = FavouriteCategory(
      id: 'category-${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
      colourValue: colourValue,
      createdAt: DateTime.now(),
    );
    await database.insert(
      'favourite_categories',
      _categoryToDatabaseMap(category),
    );
    return category;
  }

  Future<void> updateFavouriteCategory(FavouriteCategory category) async {
    final database = await _db;
    await database.update(
      'favourite_categories',
      _categoryToDatabaseMap(category),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<void> deleteFavouriteCategory(String categoryId) async {
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
      where: 'category_id = ?',
      whereArgs: [categoryId],
    );
    await database.delete(
      'favourite_categories',
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  Future<void> addFavourite(FavouriteItem favourite) async {
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
      where: 'id = ?',
      whereArgs: [favourite.categoryId],
      limit: 1,
    );
    if (category.isEmpty) {
      throw StateError('The selected favourite category no longer exists.');
    }
    await database.insert(
      'favourites',
      _favouriteToDatabaseMap(favourite),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> updateFavourite(FavouriteItem favourite) async {
    final database = await _db;
    await database.update(
      'favourites',
      _favouriteToDatabaseMap(favourite),
      where: 'id = ?',
      whereArgs: [favourite.id],
    );
  }

  Future<void> deleteFavourite(String id) async {
    final database = await _db;
    await database.delete('favourites', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<FavouriteItem>> getFavourites({String? categoryId}) async {
    final database = await _db;
    final rows = await database.query(
      'favourites',
      where: categoryId == null ? null : 'category_id = ?',
      whereArgs: categoryId == null ? null : [categoryId],
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
    final database = await _db;
    final rows = await database.query(
      'service_usage',
      columns: ['usage_count'],
      where: 'route_id = ?',
      whereArgs: [route.id],
      limit: 1,
    );
    final previousCount = rows.isEmpty ? 0 : rows.first['usage_count'] as int;
    await database.insert('service_usage', {
      'route_id': route.id,
      'route_number': route.number,
      'route_name': route.name,
      'mode': route.mode,
      'usage_count': previousCount + 1,
      'last_used_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ServiceUsage>> getFrequentServices({int limit = 4}) async {
    final database = await _db;
    final rows = await database.query(
      'service_usage',
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

  Map<String, Object?> _savedJourneyToDatabaseMap(SavedJourney journey) {
    return {
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

  Map<String, Object?> _categoryToDatabaseMap(FavouriteCategory category) {
    return {
      'id': category.id,
      'name': category.name,
      'colour_value': category.colourValue,
      'created_at': category.createdAt.toIso8601String(),
    };
  }

  Map<String, Object?> _favouriteToDatabaseMap(FavouriteItem favourite) {
    return {
      'id': favourite.id,
      'title': favourite.title,
      'subtitle': favourite.subtitle,
      'type': favourite.type,
      'reference_id': favourite.referenceId,
      'category_id': favourite.categoryId,
      'created_at': favourite.createdAt.toIso8601String(),
    };
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
    final database = await _db;
    final completedAt = DateTime.now();

    final journeyId = 'completed-${completedAt.microsecondsSinceEpoch}';

    await database.transaction((transaction) async {
      await transaction.insert('completed_journeys', {
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
    final database = await _db;

    final conditions = <String>[];
    final arguments = <Object?>[];

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
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'completed_at DESC',
    );

    final journeys = <CompletedJourney>[];

    for (final journeyRow in journeyRows) {
      final journeyId = journeyRow['id'] as String;

      final legRows = await database.query(
        'completed_journey_legs',
        where: 'journey_id = ?',
        whereArgs: [journeyId],
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
    final database = await _db;

    final rows = await database.query(
      'monthly_travel_budgets',
      where: 'month_key = ?',
      whereArgs: [_monthKey(month)],
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
    final database = await _db;

    await database.insert('monthly_travel_budgets', {
      'month_key': _monthKey(month),
      'amount': amount,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Delete a completed journey
  Future<void> deleteCompletedJourney(String journeyId) async {
    final database = await _db;

    await database.transaction((transaction) async {
      await transaction.delete(
        'completed_journey_legs',
        where: 'journey_id = ?',
        whereArgs: [journeyId],
      );

      await transaction.delete(
        'completed_journeys',
        where: 'id = ?',
        whereArgs: [journeyId],
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
    final database = await _db;

    await database.insert(
      'users',
      {
        'full_name': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'password_hash': _hashPassword(password),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<AppUser?> loginUser({
    required String email,
    required String password,
  }) async {
    final database = await _db;
    final normalisedEmail = email.trim().toLowerCase();

    final rows = await database.query(
      'users',
      where: 'email = ?',
      whereArgs: [normalisedEmail],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    final userRow = rows.first;
    final savedPasswordHash =
    userRow['password_hash'] as String;
    final enteredPasswordHash =
    _hashPassword(password);

    if (savedPasswordHash != enteredPasswordHash) {
      return null;
    }

    return AppUser.fromMap(userRow);
  }

  Future<AccessibilityPreferences> getAccessibilityPreferences() async {
    final database = await _db;
    final rows = await database.query(
      'accessibility_preferences',
      where: 'id = 1',
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
    final database = await _db;
    await database.insert('accessibility_preferences', {
      'id': 1,
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
    final database = await _db;
    final rows = await database.query(
      'accessibility_observations',
      where: stopId == null ? null : 'stop_id = ?',
      whereArgs: stopId == null ? null : [stopId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_accessibilityObservationFromMap).toList();
  }

  Future<void> saveAccessibilityObservation(
      AccessibilityObservation observation,
      ) async {
    final database = await _db;
    await database.insert('accessibility_observations', {
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
    final database = await _db;
    await database.delete(
      'accessibility_observations',
      where: 'id = ?',
      whereArgs: [id],
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

Future<void> _createAccessibilityTables(Database database) async {
  await database.execute('''
    CREATE TABLE IF NOT EXISTS accessibility_preferences(
      id INTEGER PRIMARY KEY CHECK(id = 1),
      selected_needs TEXT NOT NULL,
      accessible_routes_only INTEGER NOT NULL,
      working_lifts_only INTEGER NOT NULL,
      audio_guidance INTEGER NOT NULL,
      visual_alerts INTEGER NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE TABLE IF NOT EXISTS accessibility_observations(
      id TEXT PRIMARY KEY,
      stop_id TEXT NOT NULL,
      stop_name TEXT NOT NULL,
      facility TEXT NOT NULL,
      status TEXT NOT NULL,
      note TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
  await database.execute(
    'CREATE INDEX IF NOT EXISTS accessibility_observations_stop_index '
        'ON accessibility_observations(stop_id, created_at DESC)',
  );
}
