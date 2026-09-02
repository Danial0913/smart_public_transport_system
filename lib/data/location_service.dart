import 'package:location/location.dart';

class LocationService {
  final Location _location = Location();
  String? lastErrorMessage;

  static bool isInsideMalaysia(double latitude, double longitude) {
    return latitude >= 0.8 &&
        latitude <= 7.6 &&
        longitude >= 99.5 &&
        longitude <= 119.5;
  }

  Future<LocationData?> getCurrentLocation() async {
    lastErrorMessage = null;
    var gpsEnabled = await _location.serviceEnabled();
    if (!gpsEnabled) {
      gpsEnabled = await _location.requestService();
    }

    if (!gpsEnabled) {
      lastErrorMessage = 'Please turn on the device location service.';
      return null;
    }

    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    if (permission == PermissionStatus.deniedForever) {
      lastErrorMessage =
          'Location permission is permanently denied. Enable it in system settings.';
      return null;
    }
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.grantedLimited) {
      lastErrorMessage = 'Location permission was not granted.';
      return null;
    }

    try {
      final result = await _location.getLocation().timeout(
        const Duration(seconds: 15),
      );
      final latitude = result.latitude;
      final longitude = result.longitude;
      if (!isInsideMalaysia(latitude, longitude)) {
        lastErrorMessage =
            'The reported GPS position is outside Malaysia. Choose a location on the map instead.';
        return null;
      }
      return result;
    } catch (_) {
      lastErrorMessage = 'Unable to receive a GPS location within 15 seconds.';
      return null;
    }
  }
}
