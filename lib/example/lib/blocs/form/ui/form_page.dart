import 'package:flutter/material.dart';
import 'form_with_animation.dart';

class FormPage extends StatelessWidget {
  const FormPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Form'),
      ),
      body: const FormWithAnimation(),
    );
  }
}
