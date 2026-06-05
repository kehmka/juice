import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_forms/juice_forms.dart';

/// Records the rebuild groups emitted by a bloc, so we can assert selective
/// refresh (which fields' widgets would rebuild).
class GroupRecorder {
  final List<Set<String>> emissions = [];
  late final StreamSubscription _sub;
  GroupRecorder(FormsBloc bloc) {
    _sub = bloc.stream.listen((status) {
      final g = status.event?.groupsToRebuild;
      if (g != null) emissions.add(g);
    });
  }
  Set<String> get last => emissions.last;
  void clear() => emissions.clear();
  Future<void> cancel() => _sub.cancel();
}

/// Async validator with a controllable delay; records the values it saw.
class RecordingAsyncValidator {
  final Duration delay;
  final String invalidValue;
  final List<Object?> calls = [];
  RecordingAsyncValidator({
    this.delay = const Duration(milliseconds: 40),
    this.invalidValue = 'taken',
  });

  Future<String?> call(Object? value, Map<String, Object?> values) async {
    calls.add(value);
    await Future<void>.delayed(delay);
    return value == invalidValue ? 'Taken' : null;
  }
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('FormsState / FieldState model', () {
    test('defaults', () {
      const s = FormsState();
      expect(s.fields, isEmpty);
      expect(s.isValid, isTrue);
      expect(s.submitting, isFalse);
      expect(s.submitted, isFalse);
    });

    test('dirty/valid are derived', () {
      const a = FieldState(value: 'x', initialValue: 'x');
      expect(a.dirty, isFalse);
      expect(a.valid, isTrue);
      const b = FieldState(value: 'y', initialValue: 'x', error: 'bad');
      expect(b.dirty, isTrue);
      expect(b.valid, isFalse);
    });

    test('copyWith can set value/error to null', () {
      const a = FieldState(value: 'x', error: 'bad');
      final b = a.copyWith(value: null, error: null);
      expect(b.value, isNull);
      expect(b.error, isNull);
    });
  });

  group('Validators', () {
    test('required / email / matches', () {
      expect(Validators.required()('', {}), 'Required');
      expect(Validators.required()('x', {}), isNull);
      expect(Validators.email()('nope', {}), isNotNull);
      expect(Validators.email()('a@b.com', {}), isNull);
      final m = Validators.matches('password');
      expect(m('secret', {'password': 'secret'}), isNull);
      expect(m('typo', {'password': 'secret'}), 'Does not match');
    });
  });

  group('Sync validation', () {
    test('first error wins; clears when valid', () async {
      final bloc = FormsBloc.withConfig(FormsConfig(fields: [
        FieldConfig(
          name: 'email',
          validators: [Validators.required(), Validators.email()],
        ),
      ]));
      await settle();

      bloc.change('email', '');
      await settle();
      expect(bloc.state.fields['email']!.error, 'Required');

      bloc.change('email', 'nope');
      await settle();
      expect(bloc.state.fields['email']!.error, 'Enter a valid email');

      bloc.change('email', 'a@b.com');
      await settle();
      expect(bloc.state.fields['email']!.error, isNull);
      expect(bloc.state.isValid, isTrue);

      await bloc.close();
    });

    test('cross-field matches', () async {
      final bloc = FormsBloc.withConfig(FormsConfig(fields: [
        const FieldConfig(name: 'password'),
        FieldConfig(name: 'confirm', validators: [Validators.matches('password')]),
      ]));
      await settle();

      bloc.change('password', 'secret');
      bloc.change('confirm', 'typo');
      await settle();
      expect(bloc.state.fields['confirm']!.error, 'Does not match');

      bloc.change('confirm', 'secret');
      await settle();
      expect(bloc.state.fields['confirm']!.error, isNull);

      await bloc.close();
    });
  });

  group('Selective refresh', () {
    test('changing one field emits only its group (+ any)', () async {
      final bloc = FormsBloc.withConfig(const FormsConfig(fields: [
        FieldConfig(name: 'email'),
        FieldConfig(name: 'password'),
      ]));
      await settle();

      final rec = GroupRecorder(bloc);
      bloc.change('email', 'a@b.com');
      await settle();

      expect(rec.last, contains(FormsGroups.field('email')));
      expect(rec.last, contains(FormsGroups.any));
      expect(rec.last, isNot(contains(FormsGroups.field('password'))));

      await rec.cancel();
      await bloc.close();
    });

    test('valid group only emitted when validity flips', () async {
      final bloc = FormsBloc.withConfig(FormsConfig(fields: [
        FieldConfig(name: 'email', validators: [Validators.required()]),
      ]));
      await settle();

      final rec = GroupRecorder(bloc);
      bloc.change('email', ''); // valid (never-validated) -> invalid: flips
      await settle();
      expect(rec.last, contains(FormsGroups.valid));

      rec.clear();
      bloc.change('email', 'y'); // invalid -> valid: flips
      await settle();
      expect(rec.last, contains(FormsGroups.valid));

      rec.clear();
      bloc.change('email', 'z'); // valid -> valid: no flip
      await settle();
      expect(rec.last, isNot(contains(FormsGroups.valid)));

      await rec.cancel();
      await bloc.close();
    });
  });

  group('Async validation', () {
    test('marks validating, then resolves to an error', () async {
      final av = RecordingAsyncValidator();
      final bloc = FormsBloc.withConfig(FormsConfig(fields: [
        FieldConfig(
          name: 'user',
          asyncDebounce: const Duration(milliseconds: 5),
          asyncValidator: av.call,
        ),
      ]));
      await settle();

      bloc.change('user', 'taken');
      await settle(15); // past debounce, async in flight
      expect(bloc.state.fields['user']!.validating, isTrue);

      await settle(60);
      expect(bloc.state.fields['user']!.validating, isFalse);
      expect(bloc.state.fields['user']!.error, 'Taken');

      await bloc.close();
    });

    test('stale async result is dropped when the field changes again',
        () async {
      final av = RecordingAsyncValidator(delay: const Duration(milliseconds: 40));
      final bloc = FormsBloc.withConfig(FormsConfig(fields: [
        FieldConfig(
          name: 'user',
          asyncDebounce: const Duration(milliseconds: 5),
          asyncValidator: av.call,
        ),
      ]));
      await settle();

      bloc.change('user', 'taken'); // would be invalid
      await settle(15); // past debounce; 40ms check now in flight
      bloc.change('user', 'free'); // newer value; bumps token
      await settle(80); // let both checks resolve

      expect(av.calls, contains('taken'));
      expect(av.calls, contains('free'));
      // The stale 'taken' result must NOT have overwritten 'free'.
      expect(bloc.value<String>('user'), 'free');
      expect(bloc.state.fields['user']!.error, isNull);

      await bloc.close();
    });
  });

  group('Submit', () {
    test('valid form runs the handler and marks submitted', () async {
      Map<String, Object?>? received;
      final bloc = FormsBloc.withConfig(FormsConfig(
        fields: [FieldConfig(name: 'email', validators: [Validators.required()])],
        onSubmit: (values) async => received = values,
      ));
      await settle();

      bloc.change('email', 'a@b.com');
      bloc.submit();
      await settle();

      expect(received, {'email': 'a@b.com'});
      expect(bloc.state.submitted, isTrue);
      expect(bloc.state.submitting, isFalse);

      await bloc.close();
    });

    test('invalid form does not submit; touches fields', () async {
      var called = false;
      final bloc = FormsBloc.withConfig(FormsConfig(
        fields: [FieldConfig(name: 'email', validators: [Validators.required()])],
        onSubmit: (_) async => called = true,
      ));
      await settle();

      bloc.submit();
      await settle();

      expect(called, isFalse);
      expect(bloc.state.fields['email']!.error, 'Required');
      expect(bloc.state.fields['email']!.touched, isTrue);
      expect(bloc.state.submitted, isFalse);

      await bloc.close();
    });

    test('no handler fails loudly with submitError', () async {
      final bloc = FormsBloc.withConfig(const FormsConfig(
        fields: [FieldConfig(name: 'x')],
      ));
      await settle();

      bloc.submit();
      await settle();

      expect(bloc.state.submitError, contains('No submit handler'));
      expect(bloc.state.submitted, isFalse);

      await bloc.close();
    });

    test('handler throw surfaces as submitError', () async {
      final bloc = FormsBloc.withConfig(FormsConfig(
        fields: [const FieldConfig(name: 'x')],
        onSubmit: (_) async => throw Exception('boom'),
      ));
      await settle();

      bloc.submit();
      await settle();

      expect(bloc.state.submitError, contains('boom'));
      expect(bloc.state.submitting, isFalse);
      expect(bloc.state.submitted, isFalse);

      await bloc.close();
    });

    test('submit awaits async validation before deciding', () async {
      final av = RecordingAsyncValidator(delay: const Duration(milliseconds: 20));
      var called = false;
      final bloc = FormsBloc.withConfig(FormsConfig(
        fields: [FieldConfig(name: 'user', asyncValidator: av.call)],
        onSubmit: (_) async => called = true,
      ));
      await settle();

      bloc.change('user', 'taken');
      bloc.submit(); // submit does its own awaited async pass
      await settle(60);

      expect(called, isFalse); // async said 'Taken'
      expect(bloc.state.fields['user']!.error, 'Taken');

      await bloc.close();
    });
  });

  group('Dynamic fields', () {
    test('register / unregister at runtime', () async {
      final bloc = FormsBloc.withConfig(const FormsConfig());
      await settle();
      expect(bloc.state.fields, isEmpty);

      bloc.register(const FieldConfig(name: 'late', initialValue: 'hi'));
      await settle();
      expect(bloc.state.fields.containsKey('late'), isTrue);
      expect(bloc.value<String>('late'), 'hi');

      bloc.unregister('late');
      await settle();
      expect(bloc.state.fields.containsKey('late'), isFalse);

      await bloc.close();
    });
  });

  group('Reset', () {
    test('restores initial values and clears dirty', () async {
      final bloc = FormsBloc.withConfig(const FormsConfig(fields: [
        FieldConfig(name: 'email', initialValue: 'init'),
      ]));
      await settle();

      bloc.change('email', 'changed');
      await settle();
      expect(bloc.state.fields['email']!.dirty, isTrue);

      bloc.reset();
      await settle();
      expect(bloc.value<String>('email'), 'init');
      expect(bloc.state.fields['email']!.dirty, isFalse);
      expect(bloc.state.submitted, isFalse);

      await bloc.close();
    });
  });
}
