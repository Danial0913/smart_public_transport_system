import 'dart:async';

import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as handler;

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
    var permissionGranted =
        await handler.Permission.locationWhenInUse.isGranted;
    if (!permissionGranted) {
      final permissionStatus =
          await handler.Permission.locationWhenInUse.request();
      permissionGranted =
          permissionStatus == handler.PermissionStatus.granted;
      if (!permissionGranted) {
        lastErrorMessage = 'Location permission was not granted.';
        return null;
      }
    }

    var gpsEnabled =
        await handler.Permission.location.serviceStatus.isEnabled;
    if (!gpsEnabled) {
      gpsEnabled = await _location.requestService();
    }

    if (!gpsEnabled) {
      lastErrorMessage = 'Please turn on the device location service.';
      return null;
    }

    final result = Completer<LocationData?>();
    LocationData? lastLocation;

    // Use the same continuous location stream taught in Practical 13. Ignore
    // an old foreign reading and wait for the next valid Malaysian update.
    late StreamSubscription<LocationData> subscription;
    subscription = _location.onLocationChanged.listen(
      (currentLocation) {
        lastLocation = currentLocation;
        final latitude = currentLocation.latitude;
        final longitude = currentLocation.longitude;
        if (latitude != null &&
            longitude != null &&
            isInsideMalaysia(latitude, longitude) &&
            !result.isCompleted) {
          result.complete(currentLocation);
        }
      },
      onError: (_) {
        if (!result.isCompleted) {
          result.complete(null);
        }
      },
    );

    final timer = Timer(const Duration(seconds: 30), () {
      if (!result.isCompleted) {
        result.complete(null);
      }
    });

    final location = await result.future;
    timer.cancel();
    await subscription.cancel();

    if (location == null) {
      final rejectedLatitude = lastLocation?.latitude;
      final rejectedLongitude = lastLocation?.longitude;
      if (rejectedLatitude != null && rejectedLongitude != null) {
        lastErrorMessage =
            'The device reported ${rejectedLatitude.toStringAsFixed(5)}, '
            '${rejectedLongitude.toStringAsFixed(5)}, which is outside '
            'Malaysia. No Malaysian GPS update was received.';
      } else {
        lastErrorMessage = 'Unable to receive a GPS location. Please try again.';
      }
    }
    return location;
  }
}
