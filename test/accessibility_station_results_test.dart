import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_public_transport_system/data/accessibility_service.dart';
import 'package:smart_public_transport_system/models/transit_models.dart';
import 'package:smart_public_transport_system/screens/accessibility/accessibility_station_results_screen.dart';

AccessibilityStationSearch searchWith(int count, {VoidCallback? onProfile}) {
  return AccessibilityStationSearch(
    stops: List.generate(
      count,
      (index) => TransitStop(
        id: 'stop:$index',
        name: 'Station ${index.toString().padLeft(3, '0')}',
        latitude: 5.4,
        longitude: 100.3,
        accessible: true,
        accessibilityKnown: true,
      ),
    ),
    profileForStop: (stop) {
      onProfile?.call();
      return AccessibilityService.instance.profileForStop(stop, const []);
    },
  );
}

Widget resultsApp(Future<AccessibilityStationSearch> Function() loader) {
  return MaterialApp(
    home: AccessibilityStationResultsScreen(
      region: AccessibilityService.regions.first,
      query: '',
      requiredFacilities: const {},
      searchLoader: loader,
    ),
  );
}

Future<void> reachBottom(WidgetTester tester) async {
  final list = tester.widget<ListView>(find.byType(ListView));
  // Variable-height lazy rows refine the scroll extent as more rows appear.
  for (var attempt = 0; attempt < 10; attempt++) {
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await tester.pump();
    if (list.controller!.position.extentAfter == 0) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  test('Pages materialize only requested stops without gaps or duplicates', () {
    var profiles = 0;
    final search = searchWith(205, onProfile: () => profiles++);
    expect(profiles, 0);
    final first = search.page(offset: 0);
    expect(first.length, 100);
    expect(profiles, 100);
    final second = search.page(offset: 100);
    final last = search.page(offset: 200);
    expect(second.length, 100);
    expect(last.length, 5);
    expect(profiles, 205);
    expect(
      [...first, ...second, ...last].map((s) => s.stop.id).toSet().length,
      205,
    );
    expect(search.page(offset: 205), isEmpty);
    expect(() => search.page(offset: -1), throwsRangeError);
  });

  testWidgets('Scrolling loads 100, then 100, then the remaining stops', (
    tester,
  ) async {
    var profiles = 0;
    await tester.pumpWidget(
      resultsApp(() async => searchWith(205, onProfile: () => profiles++)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 100 of 205 suitable stops'), findsOneWidget);
    expect(profiles, 100);
    expect(find.byType(Checkbox).evaluate().length, lessThan(100));
    expect(find.byIcon(Icons.elevator_outlined), findsNothing);
    expect(find.byIcon(Icons.escalator_warning), findsNothing);
    expect(find.byIcon(Icons.wc), findsNothing);
    expect(find.byIcon(Icons.accessible), findsWidgets);

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Showing 200 of 205 suitable stops'), findsOneWidget);
    expect(profiles, 200);

    await reachBottom(tester);
    expect(find.text('Showing 205 of 205 suitable stops'), findsOneWidget);
    expect(profiles, 205);
    expect(find.text('All matching stops loaded'), findsOneWidget);
    expect(find.text('Station 204'), findsOneWidget);
    await reachBottom(tester);
    expect(profiles, 205);
  });

  for (final count in [0, 1, 100, 101, 200]) {
    testWidgets('Handles $count matching stops and refresh resets pagination', (
      tester,
    ) async {
      await tester.pumpWidget(resultsApp(() async => searchWith(count)));
      await tester.pumpAndSettle();
      final firstCount = count > 100 ? 100 : count;
      expect(
        find.text('Showing $firstCount of $count suitable stops'),
        findsOneWidget,
      );
      if (count == 0) {
        expect(find.textContaining('No matching stops.'), findsOneWidget);
      } else {
        await reachBottom(tester);
        expect(
          find.text('Showing $count of $count suitable stops'),
          findsOneWidget,
        );
        expect(find.text('All matching stops loaded'), findsOneWidget);
      }
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      await refresh.onRefresh();
      await tester.pumpAndSettle();
      expect(
        find.text('Showing $firstCount of $count suitable stops'),
        findsOneWidget,
      );
    });
  }

  testWidgets('Failed search can be retried', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      resultsApp(() async {
        if (attempts++ == 0) throw Exception('Unavailable');
        return searchWith(1);
      }),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load stops. Please try again.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();
    expect(find.text('Showing 1 of 1 suitable stops'), findsOneWidget);
  });

  testWidgets('Comparison selection survives loading another page', (
    tester,
  ) async {
    await tester.pumpWidget(resultsApp(() async => searchWith(101)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('1 of 2 stations selected'), findsOneWidget);
    await reachBottom(tester);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 stations selected'), findsOneWidget);
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();
    expect(find.text('Station 000'), findsWidgets);
    expect(find.text('Station 100'), findsWidgets);
  });

  testWidgets('Leaving during loading does not update disposed state', (
    tester,
  ) async {
    final completer = Completer<AccessibilityStationSearch>();
    await tester.pumpWidget(resultsApp(() => completer.future));
    await tester.pumpWidget(const SizedBox());
    completer.complete(searchWith(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
