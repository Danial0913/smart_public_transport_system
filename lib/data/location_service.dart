import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

class LocationService {
  final Location _location = Location();

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

    return _location.getLocation();
  }
}
