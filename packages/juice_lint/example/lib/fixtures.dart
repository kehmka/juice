// Fixtures for juice_lint. Each marked line MUST trigger its rule; lines
// without a marker must stay clean (custom_lint fails the run if a rule
// over-fires). Verified by `dart run custom_lint`. The markers are the
// comments below, one line above each offending declaration.
import 'package:juice/juice.dart';

// --- juice_generic_event ---------------------------------------------------

// expect_lint: juice_generic_event
class BadGenericEvent<T> extends EventBase {} // generic → never matches

class GoodEvent extends EventBase {} // non-generic → fine

// --- juice_mutable_state_field & juice_behavior_in_state --------------------

class BadState extends BlocState {
  // expect_lint: juice_mutable_state_field
  int count = 0; // non-final → mutable state

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
