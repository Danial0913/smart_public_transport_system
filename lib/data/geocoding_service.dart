import 'package:geocoding/geocoding.dart';

import '../models/transit_models.dart';
import 'location_service.dart';

class GeocodingService {
  final Geocoding _geocoding = Geocoding();

  Future<String?> getPlaceName(double latitude, double longitude) async {
    try {
      final placemarks = await _geocoding
          .placemarkFromCoordinates(latitude, longitude)
          .timeout(const Duration(seconds: 10));
      if (placemarks.isEmpty) return null;
      return _formatPlacemark(placemarks.first);
    } catch (_) {
      return null;
    }
  }

  Future<JourneyLocation?> searchLocation(String searchText) async {
    final query = searchText.trim();
    if (query.isEmpty) return null;

    try {
      final locations = await _geocoding
          .locationFromAddress('$query, Malaysia')
          .timeout(const Duration(seconds: 10));

      for (final location in locations) {
        if (!LocationService.isInsideMalaysia(
          location.latitude,
          location.longitude,
        )) {
          continue;
        }

        final placeName = await getPlaceName(
          location.latitude,
          location.longitude,
        );
        return JourneyLocation(
          name: placeName ?? query,
          latitude: location.latitude,
          longitude: location.longitude,
        );
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _formatPlacemark(Placemark placemark) {
    final parts = <String>[];
    final possibleParts = [
      placemark.name,
      placemark.subLocality,
      placemark.locality,
    ];

    for (final part in possibleParts) {
      final value = part?.trim() ?? '';
      if (value.isNotEmpty && !parts.contains(value)) {
        parts.add(value);
      }
    }

    if (parts.isEmpty) return 'Selected location';
    return parts.take(2).join(', ');
  }
}
