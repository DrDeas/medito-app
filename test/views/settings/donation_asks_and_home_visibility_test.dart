import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medito/constants/enums/home_widget_type.dart';
import 'package:medito/constants/strings/shared_preference_constants.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/home/widget_order_provider.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/views/home/customise_home_layout_screen.dart';
import 'package:medito/views/settings/widgets/donation_asks_tile.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _mount(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeWidgetOrderClockProvider.overrideWithValue(
          () => DateTime(2026, 1, 1),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return prefs;
}

void main() {
  testWidgets('donation reminders can be turned off and back on', (
    tester,
  ) async {
    final prefs = await _mount(
      tester,
      const Scaffold(
        body: DonationAsksTile(icon: Icon(Icons.notifications_paused_outlined)),
      ),
    );

    // The row draws its title and current value as one text block.
    final row = find.byType(DonationAsksTile);
    Finder rowText(String value) =>
        find.descendant(of: row, matching: find.textContaining(value));
    expect(rowText('Donation reminders'), findsOneWidget);
    expect(rowText('On'), findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Never ask me to donate'));
    await tester.pumpAndSettle();

    expect(prefs.getBool(SharedPreferenceConstants.donationAsksMuted), isTrue);
    expect(rowText('Off'), findsOneWidget);
    expect(find.text('Never ask me to donate'), findsNothing);

    await tester.tap(row);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Occasional, gentle asks after a session'));
    await tester.pumpAndSettle();

    expect(prefs.getBool(SharedPreferenceConstants.donationAsksMuted), isFalse);
    expect(rowText('On'), findsOneWidget);
  });

  testWidgets('Home sections can be switched off, except Up Next', (
    tester,
  ) async {
    final prefs = await _mount(tester, const CustomiseHomeLayoutScreen());

    // One switch per section that may be hidden.
    expect(
      find.byType(Switch),
      findsNWidgets(HomeWidgetType.values.length - 1),
    );

    final shop = find.bySemanticsLabel('Show Shop to Support on Home');
    expect(shop, findsOneWidget);
    await tester.tap(shop);
    await tester.pumpAndSettle();

    expect(prefs.getStringList(SharedPreferenceConstants.homeHiddenWidgets), [
      'products',
    ]);
  });
}
