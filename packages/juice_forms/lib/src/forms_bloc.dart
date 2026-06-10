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

  /// Active debounce timers, per field.
  final Map<String, Timer> _debounce = {};

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
                useCaseGenerator: () => InitializeFormsUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RegisterFieldEvent,
                useCaseGenerator: () => RegisterFieldUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UnregisterFieldEvent,
                useCaseGenerator: () => UnregisterFieldUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ChangeFieldEvent,
                useCaseGenerator: () => ChangeFieldUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: TouchFieldEvent,
                useCaseGenerator: () => TouchFieldUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SetFieldEnabledEvent,
                useCaseGenerator: () => SetFieldEnabledUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RunAsyncValidationEvent,
                useCaseGenerator: () => RunAsyncValidationUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ValidateFormEvent,
                useCaseGenerator: () => ValidateFormUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: SubmitFormEvent,
                useCaseGenerator: () => SubmitFormUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ResetFormEvent,
                useCaseGenerator: () => ResetFormUseCase()),
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
  String? syncErrorFor(String name, Object? value, Map<String, Object?> values) {
    final cfg = _configs[name];
    if (cfg == null) return null;
    for (final v in cfg.validators) {
      final err = v(value, values);
      if (err != null) return err;
    }
    return null;
  }

  AsyncValidator? asyncValidatorFor(String name) => _configs[name]?.asyncValidator;

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
  void scheduleAsyncValidation(String name) {
    final token = (_token[name] ?? 0) + 1;
    _token[name] = token;
    _debounce[name]?.cancel();
    _debounce[name] = Timer(debounceFor(name), () {
      if (!isClosed) send(RunAsyncValidationEvent(name, token));
    });
  }

  /// Invalidate any pending/in-flight async for [name] without scheduling new.
  void cancelAsyncValidation(String name) {
    _token[name] = (_token[name] ?? 0) + 1;
    _debounce.remove(name)?.cancel();
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
  void change(String name, Object? value) => send(ChangeFieldEvent(name, value));
  void touch(String name) => send(TouchFieldEvent(name));
  void setEnabled(String name, bool enabled) =>
      send(SetFieldEnabledEvent(name, enabled));
  void validate() => send(ValidateFormEvent());
  void submit() => send(SubmitFormEvent());
  void reset() => send(ResetFormEvent());

  /// Run a full (sync + awaited async) validation pass and complete with the
  /// resulting `isValid` — the awaitable form of [validate] for flows like
  /// "validate, then save".
  Future<bool> validateNow() {
    final completion = Completer<bool>();
    send(ValidateFormEvent(completion: completion));
    return completion.future;
  }

  /// Validate and, if valid, run the submit handler; completes `true` only
  /// when the handler succeeded (`false` on invalid, no handler, or throw —
  /// details surface in state as usual).
  Future<bool> submitNow() {
    final completion = Completer<bool>();
    send(SubmitFormEvent(completion: completion));
    return completion.future;
  }

  /// Typed read of a field's current value.
  T? value<T>(String name) => state.fields[name]?.value as T?;

  @override
  Future<void> close() async {
    for (final t in _debounce.values) {
      t.cancel();
    }
    _debounce.clear();
    await super.close();
  }
}
