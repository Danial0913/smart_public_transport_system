import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

class LocationService {
  final Location _location = Location();

  static bool isInsideMalaysia(double latitude, double longitude) {
    return latitude >= 0.8 &&
        latitude <= 7.6 &&
        longitude >= 99.5 &&
        longitude <= 119.5;
  }

  Future<LocationData?> getCurrentLocation() async {
    final permissionStatus =
        await handler.Permission.locationWhenInUse.request();

    if (permissionStatus != handler.PermissionStatus.granted) {
      return null;
    }

    var gpsEnabled = await _location.serviceEnabled();
    if (!gpsEnabled) {
      gpsEnabled = await _location.requestService();
    }

    if (!gpsEnabled) return null;

    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 1000,
      distanceFilter: 0,
    );

    LocationData? bestLocation;
    double? bestAccuracy;

    // Read a few GPS samples and keep the most accurate one.
    for (var attempt = 0; attempt < 3; attempt++) {
      final currentLocation = await _location
          .getLocation()
          .timeout(const Duration(seconds: 8));
      final accuracy = currentLocation.accuracy ?? 999999;

      if (bestLocation == null || accuracy < bestAccuracy!) {
        bestLocation = currentLocation;
        bestAccuracy = accuracy;
      }

      if (accuracy <= 30) break;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    return bestLocation;
  }
}
