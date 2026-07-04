import 'package:flutter_test/flutter_test.dart';

import 'package:local_tag_player/main.dart';

void main() {
  testWidgets('app mounts', (WidgetTester tester) async {
    await tester.pumpWidget(const LocalTagPlayerApp());
    await tester.pump();

    expect(find.byType(LocalTagPlayerApp), findsOneWidget);
  });
}
