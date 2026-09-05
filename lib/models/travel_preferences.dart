import 'dart:convert';
import 'transit_models.dart';

class TravelPreferences {
  const TravelPreferences({
    this.transportModes = const {'Bus', 'Train'},
    this.maximumWalkingMetres = 1500,
    this.preferLowestFare = true,
    this.preferFewerTransfers = false,
    this.travelNotifications = true,
  });
  final Set<String> transportModes;
  final int maximumWalkingMetres;
  final bool preferLowestFare;
  final bool preferFewerTransfers;
  final bool travelNotifications;
  Set<String> get plannerModes => {
    if (transportModes.contains('Bus')) 'Bus',
    if (transportModes.contains('Train')) ...{'MRT', 'LRT', 'KTM', 'Monorail'},
    if (transportModes.contains('Ferry')) 'Ferry',
  };
  String get routePreference => preferLowestFare ? 'Lowest Fee' : 'Recommended';
  Map<String, Object?> toMap() => {
    'transport_modes': jsonEncode(transportModes.toList()..sort()),
    'maximum_walking_metres': maximumWalkingMetres,
    'prefer_lowest_fare': preferLowestFare ? 1 : 0,
    'prefer_fewer_transfers': preferFewerTransfers ? 1 : 0,
    'travel_notifications': travelNotifications ? 1 : 0,
  };
  factory TravelPreferences.fromMap(Map<String, Object?> row) =>
      TravelPreferences(
        transportModes: Set.unmodifiable(
          (jsonDecode(row['transport_modes'] as String) as List).cast<String>(),
        ),
        maximumWalkingMetres: row['maximum_walking_metres'] as int,
        preferLowestFare: row['prefer_lowest_fare'] == 1,
        preferFewerTransfers: row['prefer_fewer_transfers'] == 1,
        travelNotifications: row['travel_notifications'] == 1,
      );
}

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.label,
    required this.location,
  });
  final int id;
  final String label;
  final JourneyLocation location;
  factory SavedPlace.fromMap(Map<String, Object?> row) => SavedPlace(
    id: row['id'] as int,
    label: row['label'] as String,
    location: JourneyLocation(
      name: row['location_name'] as String,
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
    ),
  );
}
