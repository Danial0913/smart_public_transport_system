import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transport_system/data/journey_notification_service.dart';
import 'package:smart_public_transport_system/data/travel_settings.dart';
import 'package:smart_public_transport_system/models/travel_preferences.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';
import 'package:smart_public_transport_system/screens/profile_screen.dart';
import 'package:smart_public_transport_system/screens/saved_places_widgets.dart';
import 'account_settings_screen_test.dart' show FakeAccount, tapVisible;

class FakeTravelSettings implements TravelSettings {
  TravelPreferences preferences = const TravelPreferences();
  final places = <SavedPlace>[];
  bool failSave = false;
  int saves = 0;
  int nextId = 1;
  @override
  Future<TravelPreferences> getTravelPreferences() async => preferences;
  @override
  Future<void> saveTravelPreferences(TravelPreferences value) async {
    if (failSave) throw StateError('Storage unavailable');
    preferences = value;
    saves++;
  }

  @override
  Future<List<SavedPlace>> getSavedPlaces() async => List.of(places);
  @override
  Future<void> savePlace({
    int? id,
    required String label,
    required JourneyLocation location,
  }) async {
    if (failSave) throw StateError('Storage unavailable');
    places.removeWhere((place) => place.id == id);
    places.add(
      SavedPlace(id: id ?? nextId++, label: label, location: location),
    );
  }

  @override
  Future<void> deletePlace(int id) async =>
      places.removeWhere((place) => place.id == id);
}

void main() {
  test('Disabled travel notifications skip platform scheduling', () async {
    final settings = FakeTravelSettings()
      ..preferences = const TravelPreferences(travelNotifications: false);
    final notifications = JourneyNotificationService.forTesting(settings);
    expect(
      await notifications.scheduleJourney(
        journeyId: 'test',
        origin: 'Home',
        destination: 'Work',
        departureTime: DateTime.now().add(const Duration(hours: 1)),
      ),
      JourneyReminderResult.disabled,
    );
  });

  testWidgets('Preferences load, save, cancel reminders and reload', (
    tester,
  ) async {
    final account = FakeAccount();
    final settings = FakeTravelSettings()
      ..preferences = const TravelPreferences(
        transportModes: {'Ferry'},
        maximumWalkingMetres: 2500,
      );
    var cancellations = 0;
    Future<void> open() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileScreen(
              account: account,
              travelSettings: settings,
              cancelReminders: () async {
                cancellations++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await open();
    final ferry = find.widgetWithText(FilterChip, 'Ferry');
    expect(tester.widget<FilterChip>(ferry).selected, true);
    await tester.tap(ferry);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(ferry).selected,
      true,
    ); // Last mode cannot be removed.
    await tester.tap(find.widgetWithText(FilterChip, 'Bus'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Travel Notifications').hitTestable(),
      250,
    );
    await tester.tap(find.text('Travel Notifications'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save Travel Preferences'), 200);
    await tapVisible(tester, 'Save Travel Preferences');
    expect(settings.preferences.transportModes, {'Bus', 'Ferry'});
    expect(settings.preferences.maximumWalkingMetres, 2500);
    expect(settings.preferences.travelNotifications, false);
    expect(cancellations, 1);
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Bus'))
          .selected,
      true,
    );
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'Ferry'))
          .selected,
      true,
    );
  });

  testWidgets(
    'Saved places can be added, selected with coordinates, edited and removed',
    (tester) async {
      final settings = FakeTravelSettings();
      const location = JourneyLocation(
        name: 'Gurney Plaza',
        latitude: 5.4371,
        longitude: 100.3095,
      );
      JourneyLocation? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                SavedPlacesCard(
                  settings: settings,
                  pickLocation: (_, _) async => location,
                ),
                SavedPlaceSelector(
                  settings: settings,
                  label: 'Use saved place as destination',
                  onSelected: (value) => selected = value,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Add Saved Place');
      await tester.enterText(
        find.byKey(const ValueKey('saved-place-label')),
        'Home',
      );
      await tapVisible(tester, 'Save Place');
      expect(find.text('Select a location for this place.'), findsOneWidget);
      await tapVisible(tester, 'Choose Location');
      settings.failSave = true;
      await tapVisible(tester, 'Save Place');
      expect(settings.places, isEmpty);
      expect(
        find.text('Could not save this place. Please try again.'),
        findsOneWidget,
      );
      settings.failSave = false;
      await tapVisible(tester, 'Save Place');
      expect(find.text('Home'), findsOneWidget);
      await tapVisible(tester, 'Use saved place as destination');
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Home'),
        ),
      );
      await tester.pumpAndSettle();
      expect(selected!.latitude, location.latitude);
      expect(selected!.longitude, location.longitude);
      await tester.tap(find.byTooltip('Manage Home'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Edit');
      await tester.enterText(
        find.byKey(const ValueKey('saved-place-label')),
        'Work',
      );
      await tapVisible(tester, 'Save Place');
      expect(find.text('Work'), findsOneWidget);
      expect(settings.places, hasLength(1));
      await tester.tap(find.byTooltip('Manage Work'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Remove');
      await tapVisible(tester, 'Cancel');
      expect(settings.places, hasLength(1));
      await tester.tap(find.byTooltip('Manage Work'));
      await tester.pumpAndSettle();
      await tapVisible(tester, 'Remove');
      await tapVisible(tester, 'Remove');
      expect(settings.places, isEmpty);
      await tapVisible(tester, 'Use saved place as destination');
      expect(
        find.text('No saved places yet. Add a place from your Profile.'),
        findsOneWidget,
      );
    },
  );
}
