import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pos_app/widgets/stat_tile.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('StatTile invokes onTap when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        StatTile(
          icon: Icons.warning_rounded,
          label: 'Low stock',
          value: '5',
          color: Colors.orange,
          onTap: () => taps++,
        ),
      ),
    );

    await tester.tap(find.byType(StatTile));
    expect(taps, 1);
  });

  testWidgets('StatTile without onTap is not tappable', (tester) async {
    await tester.pumpWidget(
      wrap(
        const StatTile(
          icon: Icons.warning_rounded,
          label: 'Low stock',
          value: '5',
          color: Colors.orange,
        ),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
  });
}