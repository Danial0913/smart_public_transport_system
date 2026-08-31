import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/transit_models.dart';

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
      version: 2,
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
          'created_at': now.add(const Duration(microseconds: 1)).toIso8601String(),
        });
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
      },
    );
  }

  Future<Database> get _db async {
    await initialise();
    return _database!;
  }

  Future<void> saveJourney(JourneyOption option) async {
    await updateSavedJourney(SavedJourney.fromOption(option));
  }

  Future<void> updateSavedJourney(SavedJourney journey) async {
    final database = await _db;
    await database.insert(
      'saved_journeys',
      _savedJourneyToDatabaseMap(journey),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SavedJourney> duplicateSavedJourney(SavedJourney journey) async {
    final duplicated = journey.copyWith(
      id: '${journey.id}-copy-${DateTime.now().microsecondsSinceEpoch}',
      departureTime: journey.departureTime.add(const Duration(days: 1)),
      savedAt: DateTime.now(),
    );
    await updateSavedJourney(duplicated);
    return duplicated;
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
    await database.delete(
      'saved_journeys',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recordSearch({
    required JourneyLocation origin,
    required JourneyLocation destination,
  }) async {
    final database = await _db;
    await database.insert(
      'recent_searches',
      {
        'origin': origin.name.trim(),
        'destination': destination.name.trim(),
        'origin_latitude': origin.latitude,
        'origin_longitude': origin.longitude,
        'destination_latitude': destination.latitude,
        'destination_longitude': destination.longitude,
        'searched_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
        destinationLatitude:
            (row['destination_latitude'] as num?)?.toDouble(),
        destinationLongitude:
            (row['destination_longitude'] as num?)?.toDouble(),
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
    await database.insert(
      'favourites',
      _favouriteToDatabaseMap(favourite),
      conflictAlgorithm: ConflictAlgorithm.replace,
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
    await database.delete(
      'favourites',
      where: 'id = ?',
      whereArgs: [id],
    );
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
        type: row['type'] as String,
        referenceId: row['reference_id'] as String,
        categoryId: row['category_id'] as String,
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
    await database.insert(
      'service_usage',
      {
        'route_id': route.id,
        'route_number': route.number,
        'route_name': route.name,
        'mode': route.mode,
        'usage_count': previousCount + 1,
        'last_used_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
      destinationLatitude:
          (row['destination_latitude'] as num?)?.toDouble(),
      destinationLongitude:
          (row['destination_longitude'] as num?)?.toDouble(),
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
}
