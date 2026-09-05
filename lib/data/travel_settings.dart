import '../models/travel_preferences.dart';
import '../models/transit_models.dart';

abstract interface class TravelSettings {
  Future<TravelPreferences> getTravelPreferences();
  Future<void> saveTravelPreferences(TravelPreferences preferences);
  Future<List<SavedPlace>> getSavedPlaces();
  Future<void> savePlace({
    int? id,
    required String label,
    required JourneyLocation location,
  });
  Future<void> deletePlace(int id);
}
