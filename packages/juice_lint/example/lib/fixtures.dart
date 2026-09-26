// Fixtures for juice_lint's state and event rules. Each `// expect_lint:`
// marker names the rule that MUST be reported on the next line; every other
// line must stay clean. `dart run tool/check_fixtures.dart` (from
// packages/juice_lint) runs `dart analyze` here and fails on any missing or
// extra diagnostic.
import 'package:juice/juice.dart';

// --- juice_generic_event ---------------------------------------------------

// expect_lint: juice_generic_event
class BadGenericEvent<T> extends EventBase {} // generic → never matches

class GoodEvent extends EventBase {} // non-generic → fine

// An abstract generic BASE is never sent itself → fine; its concrete,
// non-generic subclasses are what get sent → fine.
abstract class PayloadEvent<T> extends EventBase {
  T get payload;
}

class NamePayloadEvent extends PayloadEvent<String> {
  @override
  final String payload;
  NamePayloadEvent(this.payload);
}

// --- juice_mutable_state_field & juice_behavior_in_state --------------------

class BadState extends BlocState {
  // expect_lint: juice_mutable_state_field
  int count = 0; // non-final → mutable state (quick fix: insert `final`)

  // expect_lint: juice_behavior_in_state
  final void Function()? onTap; // a callback belongs on the bloc

  // expect_lint: juice_behavior_in_state
  final Timer? ticker; // a timer belongs on the bloc

  BadState({this.onTap, this.ticker}); // non-const: it has a mutable field
}

class GoodState extends BlocState {
  final int count;
  final List<String> items;
  const GoodState({this.count = 0, this.items = const []});

  GoodState copyWith({int? count, List<String>? items}) =>
      GoodState(count: count ?? this.count, items: items ?? this.items);
}

// A plain class with the same-shaped fields is NOT a BlocState — no lints.
class NotAState {
  int mutable = 0;
  void Function()? cb;
  NotAState();
}
