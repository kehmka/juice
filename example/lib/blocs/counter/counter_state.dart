import 'package:juice/juice.dart';

class CounterState extends BlocState {
  final int count;

  CounterState({required this.count});

  // Creates a copy of the current state with updated fields
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }

  @override
  String toString() => 'CounterState(count: $count)';
}
