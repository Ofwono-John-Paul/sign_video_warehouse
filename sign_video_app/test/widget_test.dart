import 'package:flutter_test/flutter_test.dart';
import 'package:sign_video_app/main.dart';

void main() {
  testWidgets('SignVideoApp builds without error', (WidgetTester tester) async {
    await tester.pumpWidget(const SignVideoApp());
  });
}
