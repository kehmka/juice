import 'package:juice/juice.dart';

import 'field_config.dart';
import 'forms_config.dart';
import 'forms_events.dart';
import 'forms_state.dart';
import 'forms_validators.dart';
import 'use_cases/change_field_use_case.dart';
import 'use_cases/initialize_forms_use_case.dart';
import 'use_cases/register_field_use_case.dart';
import 'use_cases/reset_form_use_case.dart';
import 'use_cases/run_async_validation_use_case.dart';
import 'use_cases/set_field_enabled_use_case.dart';
import 'use_cases/submit_form_use_case.dart';
import 'use_cases/touch_field_use_case.dart';
import 'use_cases/unregister_field_use_case.dart';
import 'use_cases/validate_form_use_case.dart';

/// A form bloc: owns the value, validation, and submit state of a set of
/// fields, with **per-field selective rebuilds**.
///
/// State (`FormsState`) holds only data. Behavior — sync/async validators,
/// debounce, the submit handler — lives here as field config, never in state.
///
/// ```dart
/// final form = FormsBloc.withConfig(FormsConfig(
///   fields: [
///     FieldConfig(name: 'email', validators: [Validators.required(), Validators.email()]),
///   ],
///   onSubmit: (values) => api.signUp(values),
/// ));
/// form.change('email', 'a@b.com');
/// form.submit();
/// ```
class FormsBloc extends JuiceBloc<FormsState> {
  /// Per-field behavior (validators/async/debounce). Not serializable state.
  final Map<String, FieldConfig> _configs = {};

  /// Monotonic validation token per field — bumped on every change so a stale
  /// async result can be dropped.
  final Map<String, int> _token = {};

  SubmitHandler? _onSubmit;

  FormsBloc()
      : super(
          FormsState.initial,
          [
            () => UseCaseBuilder(
                typeOfEvent: InitializeFormsEvent,
                useCaseGenerator: () => InitializeFormsUseCase(),
                // Configuration replaces all field behavior and the submit
                // handler; only one initialization may own that transition.
                concurrency: EventConcurrency.droppable),
            () => UseCaseBuilder(
                typeOfEvent: RegisterFieldEvent,
                useCaseGenerator: () => RegisterFieldUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: UnregisterFieldEvent,
                useCaseGenerator: () => UnregisterFieldUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: ChangeFieldEvent,
                useCaseGenerator: () => ChangeFieldUseCase(),
                // Field changes replace entries in the shared fields map and
                // update validation tokens; preserve input order.
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: TouchFieldEvent,
                useCaseGenerator: () => TouchFieldUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: SetFieldEnabledEvent,
                useCaseGenerator: () => SetFieldEnabledUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: RunAsyncValidationEvent,
                useCaseGenerator: () => RunAsyncValidationUseCase(),
                // Different fields validate independently; same-field stale
                // results are rejected by the monotonic validation token.
                concurrency: EventConcurrency.concurrent),
            () => UseCaseBuilder(
                typeOfEvent: ValidateFormEvent,
                useCaseGenerator: () => ValidateFormUseCase(),
                // Every awaitable validation must run and complete its own
                // event, while whole-form passes must not overlap.
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: SubmitFormEvent,
                useCaseGenerator: () => SubmitFormUseCase(),
                // Sequential, not droppable: every caller awaiting a submit
                // gets its own answer, and submit handlers must never overlap.
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: ResetFormEvent,
                useCaseGenerator: () => ResetFormUseCase(),
                concurrency: EventConcurrency.sequential),
          ],
        );

  /// Create and initialize in one step.
  factory FormsBloc.withConfig(FormsConfig config) {
    final bloc = FormsBloc();
    bloc.send(InitializeFormsEvent(config: config));
    return bloc;
  }

  // === Config (used by use cases) ===

  /// Apply form-level config (submit handler). Field registration is separate.
  void configureForm(FormsConfig config) => _onSubmit = config.onSubmit;

  /// The configured submit handler, if any.
  SubmitHandler? get onSubmit => _onSubmit;

  /// Store a field's behavior.
  void configureField(FieldConfig config) => _configs[config.name] = config;

  /// Drop a field's behavior and cancel any pending async.
  void removeFieldConfig(String name) {
    _configs.remove(name);
    cancelAsyncValidation(name);
  }

  /// The registered field configs (insertion order).
  Iterable<FieldConfig> get fieldConfigs => _configs.values;

  // === Validation primitives ===

  /// Run a field's sync validators against [value]; first error wins.
  String? syncErrorFor(
      String name, Object? value, Map<String, Object?> values) {
    final cfg = _configs[name];
    if (cfg == null) return null;
    for (final v in cfg.validators) {
      final err = v(value, values);
      if (err != null) return err;
    }
    return null;
  }

  AsyncValidator? asyncValidatorFor(String name) =>
      _configs[name]?.asyncValidator;

  Duration debounceFor(String name) =>
      _configs[name]?.asyncDebounce ?? Duration.zero;

  /// Full validation pass: sync then awaited async, per field. Returns
  /// name → error (null = valid). Used by validate() and submit().
  Future<Map<String, String?>> computeAllErrors() async {
    final values = state.values;
    final errors = <String, String?>{};
    for (final name in state.fields.keys) {
      final sync = syncErrorFor(name, values[name], values);
      if (sync != null) {
        errors[name] = sync;
        continue;
      }
      final av = asyncValidatorFor(name);
      errors[name] = av == null ? null : await av(values[name], values);
    }
    return errors;
  }

  // === Async token / debounce ===

  /// Arm a debounced async validation for [name], bumping its token so any
  /// in-flight check is invalidated. Fires [RunAsyncValidationEvent].
  ///
  /// The debounce is a `sendAfter` keyed by field: a later keystroke in the
  /// same field replaces the check still waiting, and the bloc owns the
  /// timer. The token still guards a check ALREADY running — a debounce
  /// cannot recall that.
  void scheduleAsyncValidation(String name) {
    final token = (_token[name] ?? 0) + 1;
    _token[name] = token;
    sendAfter(RunAsyncValidationEvent(name, token), debounceFor(name),
        key: _debounceKey(name));
  }

  static String _debounceKey(String name) => 'asyncValidation:$name';

  /// Invalidate any pending/in-flight async for [name] without scheduling new.
  void cancelAsyncValidation(String name) {
    _token[name] = (_token[name] ?? 0) + 1;
    cancelSend(_debounceKey(name));
  }

  /// Invalidate async for every field (used before validate/submit/reset).
  void cancelAllAsyncValidation() {
    for (final name in _configs.keys.toList()) {
      cancelAsyncValidation(name);
    }
  }

  /// Whether [token] is still the live token for [name] (else the result is stale).
  bool isCurrentToken(String name, int token) => _token[name] == token;

  // === Convenience API ===

  void register(FieldConfig config) => send(RegisterFieldEvent(config));
  void unregister(String name) => send(UnregisterFieldEvent(name));
  void change(String name, Object? value) =>
      send(ChangeFieldEvent(name, value));
  void touch(String name) => send(TouchFieldEvent(name));
  void setEnabled(String name, bool enabled) =>
      send(SetFieldEnabledEvent(name, enabled));
  void validate() => send(ValidateFormEvent());
  void submit() => send(SubmitFormEvent());
  void reset() => send(ResetFormEvent());

  /// Run a full (sync + awaited async) validation pass and complete with the
  /// resulting `isValid` — the awaitable form of [validate] for flows like
  /// "validate, then save".
  @Deprecated('Use sendForResult(ValidateFormEvent()): the same isValid, '
      'with a timeout and a loud failure on a closed bloc. Removed in the '
      'next major.')
  Future<bool> validateNow() {
    final event = ValidateFormEvent();
    send(event);
    return event.result;
  }

  /// Validate and, if valid, run the submit handler; completes `true` only
  /// when the handler succeeded (`false` on invalid, no handler, or throw —
  /// details surface in state as usual).
  @Deprecated('Use sendForResult(SubmitFormEvent()). It returns false when '
      'the form is invalid, and — unlike submitNow, which returned false — '
      'THROWS when no handler is configured or the handler threw. Removed '
      'in the next major.')
  Future<bool> submitNow() {
    final event = SubmitFormEvent();
    send(event);
    // As it always answered: false for anything that is not a submit that
    // succeeded.
    return event.result.then((submitted) => submitted, onError: (_) => false);
  }

  /// Typed read of a field's current value.
  T? value<T>(String name) => state.fields[name]?.value as T?;
}
