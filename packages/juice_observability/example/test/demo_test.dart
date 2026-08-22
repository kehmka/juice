import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_observability/juice_observability.dart';
import 'package:juice_observability_example/main.dart';
import 'package:juice_observability_example/telemetry_feed.dart';

void main() {
  test('app can be instantiated', () {
    expect(const DemoApp(), isA<DemoApp>());
  });

  test('telemetryLine renders kind, actor, executionId and elapsed', () {
    expect(
      telemetryLine('juice:use_case_completed', {
        'useCase': 'RecordErrorUseCase',
        'executionId': 7,
        'elapsedMicros': 1500,
      }),
      'use_case_completed  RecordErrorUseCase  #7  1.5 ms',
    );
    expect(telemetryLine('juice:bloc_lifecycle', {'bloc': 'ObservabilityBloc'}),
        'bloc_lifecycle  ObservabilityBloc');
  });

  test('isSelfTelemetry guards the feedback loop by name', () {
    expect(isSelfTelemetry({'useCase': 'AppendTelemetryUseCase'}), isTrue);
    expect(isSelfTelemetry({'bloc': 'TelemetryFeedBloc'}), isTrue);
    expect(isSelfTelemetry({'useCase': 'RecordErrorUseCase'}), isFalse);
  });

  test('the mirror feeds the panel bloc with a real start/end pair', () async {
    final feed = TelemetryFeedBloc();
    final logger = DevtoolsJuiceLogger(
      post: (kind, data) {
        if (!isSelfTelemetry(data)) feed.append(telemetryLine(kind, data));
      },
    );
    JuiceLoggerConfig.configureLogger(logger);
    addTearDown(() => JuiceLoggerConfig.configureLogger(DefaultJuiceLogger()));

    final obs = ObservabilityBloc.withConfig(ObservabilityConfig(
      reporters: const [],
    ));
    obs.breadcrumb('hello', category: 'test');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final lines = feed.state.lines;
    expect(lines.any((l) => l.startsWith('use_case_execution')), isTrue);
    expect(lines.any((l) => l.startsWith('use_case_completed')), isTrue,
        reason: 'the end entry closes the span');
    expect(lines.any((l) => l.contains('AppendTelemetry')), isFalse,
        reason: 'the feed never consumes its own telemetry');
    await obs.close();
    await feed.close();
  });
}
