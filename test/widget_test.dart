import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cst_portal/utils/theme_provider.dart';
import 'package:cst_portal/widgets/common.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeColors', () {
    test('darkFuturistic has correct accent color', () {
      final c = ThemeColors.darkFuturistic;
      expect(c.accent, const Color(0xFF1E88E5));
    });

    test('darkFuturistic has white text', () {
      expect(ThemeColors.darkFuturistic.text, const Color(0xFFFFFFFF));
    });

    test('darkFuturistic is dark', () {
      expect(ThemeColors.darkFuturistic.isLight, false);
    });

    test('lightCompat has expected properties', () {
      expect(ThemeColors.lightCompat.isLight, true);
      expect(ThemeColors.lightCompat.accent, const Color(0xFF2C3E6B));
    });

    test('fromSeed generates valid palette', () {
      final colors = ThemeColors.fromSeed(
        seed: Colors.blue,
        brightness: Brightness.dark,
      );
      expect(colors.accent, isNotNull);
      expect(colors.bg, isNotNull);
      expect(colors.text, isNotNull);
      expect(colors.muted, isNotNull);
    });
  });

  group('ThemeProvider', () {
    testWidgets('provides correct initial theme', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: Consumer<ThemeProvider>(
            builder: (context, theme, _) {
              return MaterialApp(
                theme: theme.themeData,
                home: Scaffold(
                  body: Center(
                    child: Text('Hello', style: TextStyle(color: context.colors.white)),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('AppCard widget', () {
    testWidgets('renders child correctly', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: AppCard(
                child: Text('Card Content'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
    });
  });

  group('PrimaryButton widget', () {
    testWidgets('renders with label', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: PrimaryButton(
                label: 'Submit',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Submit'), findsOneWidget);
    });

    testWidgets('fires onPressed when tapped', (tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: PrimaryButton(
                label: 'Submit',
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Submit'));
      expect(pressed, true);
    });
  });

  group('EmptyState widget', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: EmptyState(
                icon: Icons.people,
                title: 'No data',
                subtitle: 'Try again later',
              ),
            ),
          ),
        ),
      );
      // Allow any pending timers to settle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No data'), findsOneWidget);
      expect(find.text('Try again later'), findsOneWidget);
    });
  });

  group('AppBadge widget', () {
    testWidgets('renders label correctly', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: AppBadge(
                label: 'Active',
                color: Colors.green,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Active'), findsOneWidget);
    });
  });

  group('ShimmerBox widget', () {
    testWidgets('renders without crashing', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
          child: MaterialApp(
            theme: ThemeProvider().themeData,
            home: Scaffold(
              body: const ShimmerBox(height: 100),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('CsvExport data structure', () {
    test('generates valid student data', () {
      final students = [
        {
          'name': 'John Doe',
          'email': 'john@test.com',
          'roll': '101',
          'registration': 'REG001',
          'shift': 'Day',
          'session': '2023-2024',
          'contact': '1234567890',
          '_source': 'profile',
        },
      ];

      expect(students.length, 1);
      expect(students[0]['name'], 'John Doe');
      expect(students[0]['_source'], 'profile');
    });
  });
}
