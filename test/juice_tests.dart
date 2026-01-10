import 'package:flutter_test/flutter_test.dart';

import 'simple_bloc_test.dart' as simple_bloc_test;
import 'stream_status_test.dart' as stream_status_test;

void main() {
  group('Juice Framework Tests', () {
    group('Basic Bloc Tests', () {
      simple_bloc_test.main();
    });

    group('StreamStatus Tests', () {
      stream_status_test.main();
    });
  });
}
