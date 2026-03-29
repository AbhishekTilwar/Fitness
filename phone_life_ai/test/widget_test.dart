import "package:flutter_test/flutter_test.dart";
import "package:phone_life_ai/main.dart";

void main() {
  testWidgets("home title", (tester) async {
    await tester.pumpWidget(const PhoneLifeApp());
    expect(find.text("Life optimization"), findsOneWidget);
  });
}
