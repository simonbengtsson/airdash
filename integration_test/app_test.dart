import 'package:airdash/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('test home screen loaded', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Pair New Device'), findsOneWidget);
  });
}
