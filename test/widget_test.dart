import 'package:flutter_test/flutter_test.dart';
import 'package:recipebox/main.dart';

void main() {
  testWidgets('Godot launcher renders the primary controls', (tester) async {
    await tester.pumpWidget(const GodotLauncherApp());

    expect(find.text('Godot Launchpad'), findsOneWidget);
    expect(find.text('Version Selector'), findsOneWidget);
    expect(find.text('Launcher'), findsOneWidget);
    expect(find.text('Default install folder'), findsOneWidget);
  });
}
