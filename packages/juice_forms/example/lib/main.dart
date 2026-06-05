import 'package:juice/juice.dart';
import 'package:juice_forms/juice_forms.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  BlocScope.register<FormsBloc>(
    () => FormsBloc.withConfig(
      FormsConfig(
        fields: [
          FieldConfig(
            name: 'username',
            validators: [Validators.required(), Validators.minLength(3)],
            asyncValidator: _checkUsername,
          ),
          FieldConfig(
            name: 'email',
            validators: [Validators.required(), Validators.email()],
          ),
          FieldConfig(
            name: 'password',
            validators: [Validators.required(), Validators.minLength(8)],
          ),
        ],
        onSubmit: (values) async {
          // Pretend to hit an API.
          await Future<void>.delayed(const Duration(milliseconds: 400));
        },
      ),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

/// Demo async check: 'admin' is "taken". Stands in for a server round-trip.
Future<String?> _checkUsername(Object? value, Map<String, Object?> values) async {
  await Future<void>.delayed(const Duration(milliseconds: 350));
  return value == 'admin' ? 'That username is taken' : null;
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_forms demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SignUpScreen(),
    );
  }
}

class SignUpScreen extends StatelessWidget {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign up')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Each field widget binds ONLY its own group — typing in one never
          // rebuilds the others. That is the selective refresh.
          FieldInput(name: 'username', label: 'Username'),
          const SizedBox(height: 16),
          FieldInput(name: 'email', label: 'Email'),
          const SizedBox(height: 16),
          FieldInput(name: 'password', label: 'Password', obscure: true),
          const SizedBox(height: 24),
          SubmitButton(),
        ],
      ),
    );
  }
}

/// One field, rebuilding only on its own group.
class FieldInput extends StatelessJuiceWidget<FormsBloc> {
  FieldInput({super.key, required this.name, required this.label, this.obscure = false})
      : super(groups: {FormsGroups.field(name)});

  final String name;
  final String label;
  final bool obscure;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final field = bloc.state.fields[name];
    final showError = field?.touched == true && field?.error != null;

    return TextField(
      obscureText: obscure,
      onChanged: (v) => bloc.change(name, v),
      onSubmitted: (_) => bloc.touch(name),
      onTapOutside: (_) => bloc.touch(name),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorText: showError ? field!.error : null,
        suffixIcon: field?.validating == true
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
    );
  }
}

/// Submit button, rebuilding only on validity/status changes.
class SubmitButton extends StatelessJuiceWidget<FormsBloc> {
  SubmitButton({super.key}) : super(groups: {FormsGroups.valid, FormsGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    if (s.submitted) {
      return const Center(child: Text('Signed up! 🎉'));
    }
    return FilledButton(
      onPressed: (s.submitting || !s.isValid) ? null : bloc.submit,
      child: s.submitting
          ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Create account'),
    );
  }
}
