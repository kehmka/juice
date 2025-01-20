import 'package:juice/juice.dart';

abstract class _Disposable {
  void dispose();
}

/// A base class for all Juice blocs that implements state management with use cases and navigation.
///
/// JuiceBloc provides structured state management through use cases and navigation through aviators.
/// It uses [StreamStatus] to handle different states (updating, waiting, error) and supports
/// group-based widget rebuilding for performance optimization.
///
/// Example:
/// ```dart
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc()
///     : super(
///         CounterState(count: 0),
///         [
///           () => UseCaseBuilder(
///             typeOfEvent: IncrementEvent,
///             useCaseGenerator: () => IncrementUseCase()),
///         ],
///         [],
///       );
/// }
/// ```
class JuiceBloc<TState extends BlocState>
    extends Bloc<EventBase, StreamStatus<TState>> implements _Disposable {
  /// Creates a JuiceBloc with initial state and use cases.
  ///
  /// [initialState] - The initial state of the bloc
  /// [useCases] - List of use case builders that handle events
  /// [aviatorBuilders] - List of navigation builders
  /// [customLogger] - Optional custom logger implementation
  /// [errorHandler] - Custom error handler, defaults to BlocErrorHandler
  JuiceBloc(
    TState initialState,
    List<UseCaseBuilderGenerator> useCases,
    List<AviatorBuilder> aviatorBuilders, {
    JuiceLogger? customLogger,
    super.errorHandler = const BlocErrorHandler(),
  })  : logger = customLogger ?? JuiceLoggerConfig.logger,
        super(StreamStatus.updating(initialState, initialState, null)) {
    _initializeBloc(useCases, aviatorBuilders);
  }

  /// Internal logger instance
  final JuiceLogger logger;

  /// Internal storage for use case builders
  final List<UseCaseBuilderBase> _builders = [];

  /// Internal storage for aviators
  final Map<String, AviatorBase> _aviators = {};

  /// The current state of the bloc
  TState get state => currentStatus.state;

  /// The previous state of the bloc
  TState get oldState => currentStatus.oldState;

  /// Initializes the bloc with use cases and aviators
  void _initializeBloc(
    List<UseCaseBuilderGenerator> useCases,
    List<AviatorBuilder> aviatorBuilders,
  ) {
    // Register built-in use cases
    _registerBuiltInUseCases();

    // Register provided use cases
    for (var gen in useCases) {
      var builder = gen.call();
      _register(builder);
      _builders.add(builder);
    }

    // Register aviators
    for (var ab in aviatorBuilders) {
      var aviator = ab.call();
      _aviators[aviator.name] = aviator;
    }
  }

  /// Registers built-in use cases like Update and Refresh
  void _registerBuiltInUseCases() {
    _register(UseCaseBuilder(
      typeOfEvent: UpdateEvent,
      useCaseGenerator: () => UpdateUseCase(),
    ));
    _register(UseCaseBuilder(
      typeOfEvent: UpdateEvent<TState>,
      useCaseGenerator: () => UpdateUseCase(),
    ));
  }

  /// Starts the bloc by emitting an update event with current state
  void start() => send(UpdateEvent(newState: state));

  @override
  void onError(Object error, StackTrace stackTrace) {
    logger.logError('Unhandled bloc error', error, stackTrace, context: {
      'type': 'bloc_error',
      'bloc': runtimeType.toString(),
      'state': state.toString()
    });

    try {
      errorHandler.handleError(
        'Unhandled bloc error',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (e, handlerStackTrace) {
      logger.logError('Error in custom errorHandler', e, handlerStackTrace,
          context: {
            'type': 'error_handler_error',
            'bloc': runtimeType.toString()
          });
    }

    logger.log('Current state during error', context: {
      'type': 'bloc_error_state',
      'bloc': runtimeType.toString(),
      'state': state.toString()
    });

    super.onError(error, stackTrace);
  }

  /// Registers a use case with the bloc
  void _register<TEvent extends EventBase>(UseCaseBuilderBase builder) {
    Type eventType = builder.eventType;
    UseCaseGenerator handler = builder.generator;

    register<TEvent>((event, emit) async {
      void checkNavigation(TState state, String? aviatorName,
          Map<String, dynamic>? aviatorArgs) {
        if (aviatorName != null && _aviators.containsKey(aviatorName)) {
          _aviators[aviatorName]?.navigateWhere.call(aviatorArgs ?? {});
        }
      }

      void emitEvent({EventBase? event}) {
        emit(currentStatus.copyWith(event: event));
      }

      void emitUpdate({
        TState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild = rebuildAlways,
      }) {
        assert(
          !isClosed,
          'Cannot emit updates after the bloc is closed',
        );

        logger.log('Emitting update', context: {
          'type': 'state_emission',
          'status': 'update',
          'state': '$newState',
          'bloc': runtimeType.toString(),
          'groups': groupsToRebuild?.toString()
        });

        if (groupsToRebuild != null) {
          assert(
            !groupsToRebuild.contains("*") || groupsToRebuild.length == 1,
            "Cannot mix '*' with other groups",
          );

          event.groupsToRebuild = <String>{
            ...?event.groupsToRebuild,
            ...groupsToRebuild
          };
          emit(StreamStatus.updating(newState ?? state, state, event));
        } else {
          emit(StreamStatus.updating(
            newState ?? state,
            state,
            event,
          ));
        }

        checkNavigation(state, aviatorName, aviatorArgs);
      }

      void emitWaiting({
        TState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild = rebuildAlways,
      }) {
        assert(
          !isClosed,
          'Cannot emit updates after the bloc is closed',
        );

        logger.log('Emitting waiting', context: {
          'type': 'state_emission',
          'status': 'waiting',
          'state': '$newState',
          'bloc': runtimeType.toString(),
          'groups': groupsToRebuild?.toString()
        });

        event.groupsToRebuild = <String>{
          ...?event.groupsToRebuild,
          ...?groupsToRebuild
        };

        emit(StreamStatus.waiting(newState ?? state, state, event));
        checkNavigation(state, aviatorName, aviatorArgs);
      }

      void emitFailure({
        TState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild = rebuildAlways,
      }) {
        assert(
          !isClosed,
          'Cannot emit failures after the bloc is closed',
        );

        logger.log('Emitting failure', context: {
          'type': 'state_emission',
          'status': 'failure',
          'state': '$newState',
          'bloc': runtimeType.toString(),
          'groups': groupsToRebuild?.toString()
        });

        event.groupsToRebuild = <String>{
          ...?event.groupsToRebuild,
          ...?groupsToRebuild
        };

        emit(StreamStatus.failure(newState ?? state, state, event));
        checkNavigation(state, aviatorName, aviatorArgs);
      }

      void emitCancel({
        TState? newState,
        String? aviatorName,
        Map<String, dynamic>? aviatorArgs,
        Set<String>? groupsToRebuild = rebuildAlways,
      }) {
        assert(
          !isClosed,
          'Cannot emit cancels after the bloc is closed',
        );

        logger.log('Emitting cancel', context: {
          'type': 'state_emission',
          'status': 'cancel',
          'state': '$newState',
          'bloc': runtimeType.toString(),
          'groups': groupsToRebuild?.toString()
        });

        event.groupsToRebuild = <String>{
          ...?event.groupsToRebuild,
          ...?groupsToRebuild
        };

        emit(StreamStatus.canceling(newState ?? state, state, event));
        checkNavigation(state, aviatorName, aviatorArgs);
      }

      try {
        var usecase = handler.call();
        usecase.bloc = this;

        usecase.emitUpdate = ({
          Map<String, dynamic>? aviatorArgs,
          String? aviatorName,
          Set<String>? groupsToRebuild,
          BlocState? newState,
        }) =>
            emitUpdate(
              newState: newState as TState?,
              aviatorName: aviatorName,
              aviatorArgs: aviatorArgs,
              groupsToRebuild: groupsToRebuild,
            );

        usecase.emitWaiting = ({
          Map<String, dynamic>? aviatorArgs,
          String? aviatorName,
          Set<String>? groupsToRebuild,
          BlocState? newState,
        }) =>
            emitWaiting(
              newState: newState as TState?,
              aviatorName: aviatorName,
              aviatorArgs: aviatorArgs,
              groupsToRebuild: groupsToRebuild,
            );

        usecase.emitFailure = ({
          Map<String, dynamic>? aviatorArgs,
          String? aviatorName,
          Set<String>? groupsToRebuild,
          BlocState? newState,
        }) =>
            emitFailure(
              newState: newState as TState?,
              aviatorName: aviatorName,
              aviatorArgs: aviatorArgs,
              groupsToRebuild: groupsToRebuild,
            );

        usecase.emitCancel = ({
          Map<String, dynamic>? aviatorArgs,
          String? aviatorName,
          Set<String>? groupsToRebuild,
          BlocState? newState,
        }) =>
            emitCancel(
              newState: newState as TState?,
              aviatorName: aviatorName,
              aviatorArgs: aviatorArgs,
              groupsToRebuild: groupsToRebuild,
            );

        usecase.emitEvent = ({EventBase? event}) => emitEvent(event: event);

        await usecase.execute(event);
      } catch (exception, stacktrace) {
        logger.logError('Unhandled use case exception', exception, stacktrace,
            context: {
              'type': 'use_case_error',
              'bloc': runtimeType.toString(),
              'event': event.runtimeType.toString()
            });
        super.onError(exception, stacktrace);
      }
    }, eventType);

    if (builder.initialEventBuilder != null) {
      var event = builder.initialEventBuilder!.call();
      if (event.runtimeType == eventType) {
        send(event);
      }
    }
  }

  @override
  Future<void> close() async {
    logger.log("Closing bloc", context: {
      'type': 'bloc_lifecycle',
      'action': 'close',
      'bloc': runtimeType.toString()
    });

    // Close all builders
    await Future.wait<void>(_builders.map((s) => s.close()));

    // Close aviators
    await Future.wait<void>(_aviators.values.map((a) => a.close()));
    _aviators.clear();

    await super.close();
  }

  @override
  void dispose() async {
    await close();
  }
}
