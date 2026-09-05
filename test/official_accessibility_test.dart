import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transport_system/data/accessibility_service.dart';
import 'package:smart_public_transport_system/data/official_accessibility_catalog.dart';
import 'package:smart_public_transport_system/models/accessibility_models.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';
import 'package:smart_public_transport_system/screens/accessibility/accessibility_station_detail_screen.dart';
import 'package:smart_public_transport_system/screens/accessibility/accessibility_comparison_screen.dart';

TransitStop stop(String id, {bool known = false, bool accessible = true}) =>
    TransitStop(
      id: id,
      name: 'Test station',
      latitude: 3.1,
      longitude: 101.6,
      accessible: accessible,
      accessibilityKnown: known,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => OfficialAccessibilityCatalog.instance.load());

  test(
    'Imported records reference real MRT stop IDs and official pages',
    () async {
      final official =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/official_accessibility.json',
                ),
              )
              as Map<String, dynamic>;
      final transit =
          jsonDecode(
                await rootBundle.loadString('assets/data/rapid-kl-rail.json'),
              )
              as Map<String, dynamic>;
      final stops = {
        for (final s in transit['stops'] as List) s['id']: s['name'],
      };
      final ids = <String>{};
      for (final row in official['stations'] as List) {
        expect(ids.add(row['stopId'] as String), isTrue);
        expect(stops[row['stopId']], row['stopName']);
        expect(Uri.parse(row['sourceUrl'] as String).host, 'www.mymrt.com.my');
        expect(DateTime.tryParse(row['checkedOn'] as String), isNotNull);
        expect(
          (row['facilities'] as Map).keys,
          everyElement(isIn(['lift', 'accessibleToilet'])),
        );
      }
      expect(ids.length, greaterThanOrEqualTo(61));
    },
  );

  test('Official facilities populate without any user reports', () {
    final profile = AccessibilityService.instance.profileForStop(
      stop('rapid-kl-rail:PY22'),
      const [],
    );
    expect(
      profile.facilities[AccessibilityFacility.lift],
      AccessibilityFacilityStatus.available,
    );
    expect(
      profile.facilities[AccessibilityFacility.accessibleToilet],
      AccessibilityFacilityStatus.available,
    );
    expect(
      profile.facilities[AccessibilityFacility.wheelchairAccess],
      AccessibilityFacilityStatus.unknown,
    );
    expect(
      profile.facilities[AccessibilityFacility.stepFreeAccess],
      AccessibilityFacilityStatus.unknown,
    );
    expect(profile.officialFacilities!.sourceUrl, endsWith('/conlay/'));
  });

  test('User reports cannot change official or unknown facility values', () {
    final profile = AccessibilityService.instance
        .profileForStop(stop('rapid-kl-rail:PY22'), [
          AccessibilityObservation(
            id: 'old-report',
            stopId: 'rapid-kl-rail:PY22',
            stopName: 'Conlay',
            facility: AccessibilityFacility.lift,
            status: AccessibilityFacilityStatus.unavailable,
            note: 'Old local report',
            createdAt: DateTime(2026),
          ),
          AccessibilityObservation(
            id: 'old-step-free',
            stopId: 'rapid-kl-rail:PY22',
            stopName: 'Conlay',
            facility: AccessibilityFacility.stepFreeAccess,
            status: AccessibilityFacilityStatus.available,
            note: 'Unverified local report',
            createdAt: DateTime(2026),
          ),
        ]);
    expect(
      profile.facilities[AccessibilityFacility.lift],
      AccessibilityFacilityStatus.available,
    );
    expect(
      profile.facilities[AccessibilityFacility.stepFreeAccess],
      AccessibilityFacilityStatus.unknown,
    );
  });

  test('Government boarding status never implies step-free access', () {
    for (final accessible in [true, false]) {
      final profile = AccessibilityService.instance.profileForStop(
        stop('test:stop', known: true, accessible: accessible),
        const [],
      );
      expect(
        profile.facilities[AccessibilityFacility.wheelchairAccess],
        accessible
            ? AccessibilityFacilityStatus.available
            : AccessibilityFacilityStatus.unavailable,
      );
      expect(
        profile.facilities[AccessibilityFacility.stepFreeAccess],
        AccessibilityFacilityStatus.unknown,
      );
    }
  });

  test('MRT facilities are not copied to neighbouring LRT or bus stops', () {
    // MRT and LRT share the name Titiwangsa but have different station records.
    final lrt = AccessibilityService.instance.profileForStop(
      stop('rapid-kl-rail:AG3'),
      const [],
    );
    expect(lrt.officialFacilities, isNull);
    expect(
      lrt.facilities.values,
      everyElement(AccessibilityFacilityStatus.unknown),
    );
  });

  test(
    'Klang Valley lift and toilet filters return official MRT records',
    () async {
      final service = AccessibilityService.instance;
      final region = AccessibilityService.regions.firstWhere(
        (r) => r.name == 'Klang Valley',
      );
      for (final facilities in <Set<AccessibilityFacility>>[
        {},
        {AccessibilityFacility.lift},
        {AccessibilityFacility.accessibleToilet},
        {AccessibilityFacility.lift, AccessibilityFacility.accessibleToilet},
      ]) {
        final results = await service.searchStations(
          region: region,
          query: '',
          requiredFacilities: facilities,
        );
        // Kwasa Damansara has two feed IDs merged by the transit repository.
        expect(results.totalCount, 64);
        final page = results.page(offset: 0);
        expect(page.every((station) => station.hasAvailableFacilities), isTrue);
        expect(
          page.every((station) => facilities.every(station.supports)),
          isTrue,
        );
      }
      for (final facility in [
        AccessibilityFacility.wheelchairAccess,
        AccessibilityFacility.stepFreeAccess,
      ]) {
        final results = await service.searchStations(
          region: region,
          query: '',
          requiredFacilities: {facility},
        );
        // No source in this snapshot confirms these facilities; do not invent availability.
        expect(results.totalCount, 0);
      }
    },
  );

  test(
    'Filters reject stops without available facilities and require every selection',
    () {
      StationAccessibility profile(
        String id,
        Map<AccessibilityFacility, AccessibilityFacilityStatus> facilities,
      ) => StationAccessibility(
        stop: stop(id),
        facilities: facilities,
        latestObservations: const {},
      );
      final stations = [
        profile('unknown', {
          AccessibilityFacility.lift: AccessibilityFacilityStatus.unknown,
        }),
        profile('unavailable', {
          AccessibilityFacility.lift: AccessibilityFacilityStatus.unavailable,
        }),
        profile('empty', {}),
        profile('lift', {
          AccessibilityFacility.lift: AccessibilityFacilityStatus.available,
        }),
        profile('both', {
          AccessibilityFacility.lift: AccessibilityFacilityStatus.available,
          AccessibilityFacility.accessibleToilet:
              AccessibilityFacilityStatus.available,
        }),
      ];
      List<String> ids(Set<AccessibilityFacility> required) =>
          AccessibilityService.instance
              .filterStations(
                stations: stations,
                query: '',
                requiredFacilities: required,
              )
              .map((station) => station.stop.id)
              .toList();
      expect(ids({}), ['both', 'lift']);
      expect(ids({AccessibilityFacility.lift}), ['both', 'lift']);
      expect(
        ids({
          AccessibilityFacility.lift,
          AccessibilityFacility.accessibleToilet,
        }),
        ['both'],
      );
      expect(ids({AccessibilityFacility.wheelchairAccess}), isEmpty);
    },
  );

  testWidgets('Comparison hides unconfirmed facilities', (tester) async {
    final profile = AccessibilityService.instance.profileForStop(
      stop('rapid-kl-rail:PY22'),
      const [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityComparisonScreen(first: profile, second: profile),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lift'), findsOneWidget);
    expect(find.text('Accessible toilet'), findsOneWidget);
    expect(find.text('Wheelchair access'), findsNothing);
    expect(find.text('Step-free access'), findsNothing);
    expect(find.text('Unknown'), findsNothing);
  });

  testWidgets(
    'Station details use official sources and no reporting controls',
    (tester) async {
      final profile = AccessibilityService.instance.profileForStop(
        stop('rapid-kl-rail:PY22'),
        const [],
      );
      await tester.pumpWidget(
        MaterialApp(home: AccessibilityStationDetailScreen(station: profile)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lift'), findsOneWidget);
      expect(find.text('Accessible toilet'), findsOneWidget);
      expect(find.text('Wheelchair access'), findsNothing);
      expect(find.text('Step-free access'), findsNothing);
      expect(find.text('Unknown'), findsNothing);
      expect(find.text('Report Status'), findsNothing);
      expect(find.textContaining('Recent observations'), findsNothing);
      await tester.ensureVisible(find.text('Source: MRT Corp'));
      await tester.pumpAndSettle();
      expect(find.text('Source: MRT Corp'), findsOneWidget);
      expect(
        find.text(
          'https://www.mymrt.com.my/projects/putrajaya-line/stations/conlay/',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
