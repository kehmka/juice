import 'package:flutter_test/flutter_test.dart';

import 'bloc/juice_bloc_test.dart' as juice_bloc_test;
import 'bloc/stream_status_test.dart' as stream_status_test;
import 'bloc/use_case_test.dart' as use_case_test;
import 'navigation/aviator_test.dart' as aviator_test;
import 'ui/stateless_juice_widget_test.dart' as stateless_juice_widget_test;

void main() {
  group('Juice Framework Tests', () {
    group('Bloc Tests', () {
      juice_bloc_test.main();
      // stream_status_test.main();
      use_case_test.main();
    });

    group('Navigation Tests', () {
      // aviator_test.main();
    });

    group('UI Tests', () {
      stateless_juice_widget_test.main();
    });
  });
}
