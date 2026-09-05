import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transport_system/data/local_storage_service.dart';
import 'package:smart_public_transport_system/data/transit_repository.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';
import 'package:smart_public_transport_system/models/travel_preferences.dart';
import 'package:smart_public_transport_system/screens/journey_planner_screen.dart';
import 'travel_settings_storage_test.dart' show TravelDatabase;

class PlannerStorage extends LocalStorageService {
  PlannerStorage(super.database) : super.forTesting();
  @override
  Future<List<RecentSearch>> getRecentSearches({int limit = 5}) async => [];
  @override
  Future<List<SavedJourney>> getSavedJourneys() async => [];
}

void main() {
  testWidgets(
    'Plan loads saved defaults and uses saved places in both fields',
    (tester) async {
      final storage = PlannerStorage(TravelDatabase());
      await storage.loginUser(
        email: 'rider1@example.com',
        password: 'OldPassword1!',
      );
      await storage.saveTravelPreferences(
        const TravelPreferences(
          transportModes: {'Ferry'},
          maximumWalkingMetres: 3500,
          preferLowestFare: true,
          preferFewerTransfers: true,
        ),
      );
      await storage.savePlace(
        label: 'Home',
        location: const JourneyLocation(
          name: 'Gurney Plaza',
          latitude: 5.4371,
          longitude: 100.3095,
        ),
      );
      await tester.runAsync(() => TransitRepository.instance.load());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JourneyPlannerScreen(
              storage: storage,
              initialAccessibleOnly: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final field in ['origin', 'destination']) {
        await tester.tap(find.text('Use saved place as $field'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Home'),
          ),
        );
        await tester.pumpAndSettle();
      }
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(fields.map((field) => field.controller!.text), [
        'Gurney Plaza',
        'Gurney Plaza',
      ]);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilterChip, 'Ferry').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ferry'))
            .selected,
        true,
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Bus'))
            .selected,
        false,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Lowest Fee').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Lowest Fee'))
            .selected,
        true,
      );
      await tester.scrollUntilVisible(
        find.text('Prefer fewer transfers').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Prefer fewer transfers'),
            )
            .value,
        true,
      );
      expect(tester.widget<Slider>(find.byType(Slider)).value, 3500);
    },
  );
}
