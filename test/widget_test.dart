import 'package:flutter_test/flutter_test.dart';
import 'package:swasthall/main.dart';

void main() {
  testWidgets('App starts and shows Login Page', (WidgetTester tester) async {
    // 1. Build our HealthApp and trigger a frame.
    // Note: This might require mocking Supabase if you run it in a CI environment,
    // but for local testing, it checks if the HealthApp initializes.
    await tester.pumpWidget(const HealthApp());

    // 2. Verify that the Welcome text from LoginPage is found.
    // (Adjust 'Welcome Back' to whatever text is actually in your login_page.dart)
    expect(find.text('Welcome Back'), findsOneWidget);
    
    // 3. Verify that we don't see the Register page yet.
    expect(find.text('Join the Health Network'), findsNothing);
  });
}