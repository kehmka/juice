import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'counter_widgets.dart';

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter Example')),
      body: Center(
        child: CounterWidget(),
      ),
      floatingActionButton: CounterButtons(),
    );
  }
}
