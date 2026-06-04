import 'package:flutter_test/flutter_test.dart';

import 'package:juice_auth_routing_example/demo_auth_provider.dart';

void main() {
  test('demo provider can be instantiated', () {
    expect(DemoAuthProvider().name, 'email');
  });
}
