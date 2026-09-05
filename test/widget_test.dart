import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smart_public_transport_system/data/accessibility_service.dart';
import 'package:smart_public_transport_system/data/ferry_api_service.dart';
import 'package:smart_public_transport_system/data/input_validator.dart';
import 'package:smart_public_transport_system/data/malaysia_time.dart';
import 'package:smart_public_transport_system/data/transit_repository.dart';
import 'package:smart_public_transport_system/main.dart';
import 'package:smart_public_transport_system/models/accessibility_models.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';

void main() {
  testWidgets('App shows the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartTransportApp());

    expect(find.text('Smart Public Transport'), findsOneWidget);
    expect(find.text('Plan smarter. Travel better.'), findsOneWidget);

    // Dispose the splash screen so its Timer is cancelled.
    await tester.pumpWidget(const SizedBox());
  });

  test('Accessibility report validation rejects incomplete details', () {
    expect(InputValidator.accessibilityObservation(''), isNotNull);
    expect(InputValidator.accessibilityObservation('Broken'), isNotNull);
    expect(
      InputValidator.accessibilityObservation(
        'The lift beside platform two is unavailable.',
      ),
      isNull,
    );
  });

  test('Accessibility filters exclude a reported lift outage', () {
    const stop = TransitStop(
      id: 'test:stop',
      name: 'Test Station',
      latitude: 3.1,
      longitude: 101.6,
      accessible: true,
      accessibilityKnown: true,
    );
    final station = StationAccessibility(
      stop: stop,
      facilities: const {
        AccessibilityFacility.wheelchairAccess:
            AccessibilityFacilityStatus.available,
        AccessibilityFacility.stepFreeAccess:
            AccessibilityFacilityStatus.available,
        AccessibilityFacility.lift: AccessibilityFacilityStatus.unavailable,
        AccessibilityFacility.accessibleToilet:
            AccessibilityFacilityStatus.unknown,
      },
      latestObservations: const {},
    );
    final result = AccessibilityService.instance.filterStations(
      stations: [station],
      query: 'Test',
      requiredFacilities: const {AccessibilityFacility.lift},
    );
    expect(result, isEmpty);
  });

  test('Journey validation rejects incomplete and invalid requests', () {
    final futureDeparture = MalaysiaTime.nextDeparture(
      leadTime: const Duration(minutes: 30),
    );
    const penang = JourneyLocation(
      name: 'Penang',
      latitude: 5.4141,
      longitude: 100.3288,
    );
    const butterworth = JourneyLocation(
      name: 'Butterworth',
      latitude: 5.3992,
      longitude: 100.3638,
    );

    expect(
      InputValidator.journey(
        origin: null,
        destination: butterworth,
        requestedTime: futureDeparture,
        modes: const {'Bus'},
        maximumWalkingMetres: 1000,
      ),
      'Select the origin and destination on the map.',
    );
    expect(
      InputValidator.journey(
        origin: penang,
        destination: butterworth,
        requestedTime: futureDeparture,
        modes: const {},
        maximumWalkingMetres: 1000,
      ),
      'Select at least one transport mode.',
    );
  });

  test('Official Penang ferry GeoJSON is parsed into Malaysia points', () {
    final points = parsePenangRoute({
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {
            'ST_NAME': 'PENGKALAN RAJA TUN UDA-SULTAN ABDUL HALIM',
          },
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [100.3441, 5.4132],
              [100.3631, 5.3948],
            ],
          },
        },
      ],
    });

    expect(points, hasLength(2));
    expect(points.first.latitude, closeTo(5.4132, 0.000001));
    expect(points.last.longitude, closeTo(100.3631, 0.000001));
  });

  test('Ferry parser rejects unrelated or malformed route data', () {
    expect(
      () =>
          parsePenangRoute({'type': 'FeatureCollection', 'features': const []}),
      throwsFormatException,
    );
  });

  test(
    'Gurney Plaza to Penang Sentral uses the direct ferry connection',
    () async {
      final repository = TransitRepository.instance;
      const origin = JourneyLocation(
        name: 'Gurney Plaza',
        latitude: 5.43594,
        longitude: 100.30881,
      );
      const destination = JourneyLocation(
        name: 'Penang Sentral',
        latitude: 5.3948602,
        longitude: 100.3653495,
      );
      const modes = {'Bus', 'Ferry'};
      final now = DateTime.now();
      var requestedTime = DateTime(now.year, now.month, now.day, 8);
      if (!requestedTime.isAfter(now)) {
        requestedTime = requestedTime.add(const Duration(days: 1));
      }

      await repository.ensureDataForJourney(
        origin,
        destination,
        selectedModes: modes,
      );
      final routes = await repository.findJourneys(
        origin: origin,
        destination: destination,
        requestedTime: requestedTime,
        departAt: true,
        selectedModes: modes,
        accessibleOnly: false,
        fewerTransfers: false,
        maximumWalkingMetres: 2000,
        preference: 'Recommended',
      );

      expect(routes, isNotEmpty);
      expect(routes.first.modes, contains('Ferry'));
      expect(routes.first.transferCount, lessThanOrEqualTo(1));
      expect(routes.first.walkingMetres, lessThan(1000));
      expect(
        routes.first.legs.first.from.name,
        isNot(equals('Gurney Plaza')),
        reason: 'The exact stop is on the outbound side of the road.',
      );
    },
  );
}
