import '../models/transit_models.dart';
import 'location_service.dart';

class InputValidator {
  static String? categoryName(
    String value,
    Iterable<FavouriteCategory> categories, {
    String? ignoredId,
  }) {
    final name = value.trim();
    if (name.isEmpty) return 'Category name is required.';
    if (name.length < 2 || name.length > 30) {
      return 'Use between 2 and 30 characters.';
    }
    final duplicate = categories.any((item) {
      return item.id != ignoredId &&
          item.name.trim().toLowerCase() == name.toLowerCase();
    });
    return duplicate ? 'This category already exists.' : null;
  }

  static String? locationSearch(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'Enter a place name.';
    if (text.length < 2) return 'Enter at least 2 characters.';
    if (text.length > 100) return 'Location name is too long.';
    return null;
  }

  static String? accessibilityStationSearch(String value) {
    final text = value.trim();
    if (text.isNotEmpty && text.length < 2) {
      return 'Enter at least 2 characters or clear the search.';
    }
    if (text.length > 80) return 'Search is limited to 80 characters.';
    return null;
  }

  static String? accessibilityObservation(String value) {
    final note = value.trim();
    if (note.isEmpty) return 'Describe what you observed.';
    if (note.length < 10) return 'Enter at least 10 characters.';
    if (note.length > 300) return 'Keep the observation under 300 characters.';
    return null;
  }

  static String? journey({
    required JourneyLocation? origin,
    required JourneyLocation? destination,
    required DateTime requestedTime,
    required Set<String> modes,
    required double maximumWalkingMetres,
  }) {
    if (origin == null || destination == null) {
      return 'Select the origin and destination on the map.';
    }
    if (!LocationService.isInsideMalaysia(origin.latitude, origin.longitude) ||
        !LocationService.isInsideMalaysia(
          destination.latitude,
          destination.longitude,
        )) {
      return 'Origin and destination must be inside Malaysia.';
    }
    if ((origin.latitude - destination.latitude).abs() < 0.0005 &&
        (origin.longitude - destination.longitude).abs() < 0.0005) {
      return 'Origin and destination cannot be the same.';
    }
    if (modes.isEmpty) return 'Select at least one transport mode.';
    if (maximumWalkingMetres < 100 || maximumWalkingMetres > 10000) {
      return 'Walking distance must be between 100 m and 10 km.';
    }
    if (requestedTime.isBefore(
      DateTime.now().subtract(const Duration(minutes: 1)),
    )) {
      return 'Travel date and time cannot be in the past.';
    }
    return null;
  }
}
