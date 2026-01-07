import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

void main() {
  group('Aviator Tests', () {
    test('Aviator navigates correctly when triggered', () {
      // Track navigation calls
      bool navigated = false;
      Map<String, dynamic>? passedArgs;

      // Create aviator
      final aviator = Aviator(
        name: 'test-aviator',
        navigateWhere: (args) {
          navigated = true;
          passedArgs = args;
        },
      );

      // Trigger navigation
      aviator.navigateWhere({'route': '/test', 'id': 123});

      // Verify navigation occurred
      expect(navigated, true);
      expect(passedArgs, isNotNull);
      expect(passedArgs!['route'], '/test');
      expect(passedArgs!['id'], 123);
    });
  });
}
