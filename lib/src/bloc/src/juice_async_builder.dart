import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

typedef InitiatorFn<T> = void Function();

/// Signature for a function that builds a widget from a value.
typedef ValueBuilderFn<T> = Widget Function(BuildContext context, T value);

/// Signature for a function that builds a widget from an exception.
typedef ErrorBuilderFn<T> = Widget Function(
    BuildContext context, T? value, Object error, StackTrace? stackTrace);

/// Signature for a function that reports a flutter error, e.g. [FlutterError.reportError].
typedef ErrorReporterFn = void Function(FlutterErrorDetails details);

class JuiceAsyncBuilder<T> extends StatefulWidget {
  final InitiatorFn<T>? initiator;

  /// The builder that should be called when no data is available.
  final ValueBuilderFn<T>? waiting;

  /// The default value builder.
  final ValueBuilderFn<T> builder;

  /// The builder that should be called when an error was thrown by the future
  /// or stream.
  final ErrorBuilderFn? error;

  /// The builder that should be called when the stream is closed.
  final ValueBuilderFn<T>? closed;

  /// If provided, this is the future the widget listens to.
  final Future<T>? future;

  /// If provided, this is the stream the widget listens to.
  final Stream<T>? stream;

  /// The initial value used before one is available.
  final T? initial;

  /// Whether or not the current value should be retained when the [stream] or
  /// [future] instances change.
  final bool retain;

  /// Whether or not to suppress printing errors to the console.
  final bool silent;

  /// Whether or not to pause the stream subscription.
  final bool pause;

  /// If provided, overrides the function that prints errors to the console.
  final ErrorReporterFn reportError;

  /// Whether or not we should send a keep alive
  /// notification with [AutomaticKeepAliveClientMixin].
  final bool keepAlive;

  /// Creates a widget that builds depending on the state of a [Future] or [Stream].
  const JuiceAsyncBuilder({
    super.key,
    this.waiting,
    this.initiator,
    required this.builder,
    this.error,
    this.closed,
    this.future,
    this.stream,
    this.initial,
    this.retain = false,
    this.pause = false,
    bool? silent,
    this.keepAlive = false,
    ErrorReporterFn? reportError,
  })  : silent = silent ?? error != null,
        reportError = reportError ?? FlutterError.reportError,
        assert(!((future != null) && (stream != null)),
            'AsyncBuilder should be given either a stream or future'),
        assert(future == null || closed == null,
            'AsyncBuilder should not be given both a future and closed builder');

  @override
  State<StatefulWidget> createState() => _JuiceAsyncBuilderState<T>();
}

class _JuiceAsyncBuilderState<T> extends State<JuiceAsyncBuilder<T>>
    with AutomaticKeepAliveClientMixin {
  late final ValueNotifier<AsyncSnapshot<T>> _snapshotNotifier;

  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();

    // Initialize the ValueNotifier with the initial state
    _snapshotNotifier = ValueNotifier<AsyncSnapshot<T>>(
        AsyncSnapshot<T>.withData(
            ConnectionState.none,
            widget.initial ??
                (throw ArgumentError("widget.initial must not be null"))));

    // Initialize the appropriate source (Future or Stream)
    if (widget.future != null) {
      _initFuture();
    } else if (widget.stream != null) {
      _initStream();
      _updatePause();
      widget.initiator?.call();
    }
  }

  void _initFuture() {
    _cancel();
    final Future<T> future = widget.future!;
    _snapshotNotifier.value = AsyncSnapshot<T>.withData(
        ConnectionState.none,
        widget.initial ??
            (throw ArgumentError("widget.initial must not be null")));

    future.then((T value) {
      if (future != widget.future || !mounted) return;
      _snapshotNotifier.value =
          AsyncSnapshot<T>.withData(ConnectionState.done, value);
    }).catchError((error, stackTrace) {
      _snapshotNotifier.value =
          AsyncSnapshot<T>.withError(ConnectionState.done, error, stackTrace);
      if (!widget.silent) {
        widget.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            context: ErrorDescription('While resolving future in AsyncBuilder'),
          ),
        );
      }
    });
  }

  void _initStream() {
    _cancel();
    final Stream<T> stream = widget.stream!;
    _snapshotNotifier.value = AsyncSnapshot<T>.withData(
        ConnectionState.none,
        widget.initial ??
            (throw ArgumentError("widget.initial must not be null")));

    bool skipFirst = false;
    if (stream is ValueStream<T> && stream.hasValue) {
      skipFirst = true;
      _snapshotNotifier.value =
          AsyncSnapshot<T>.withData(ConnectionState.active, stream.value);
    }

    _subscription = stream.listen(
      (T event) {
        if (skipFirst) {
          skipFirst = false;
          return;
        }
        _snapshotNotifier.value =
            AsyncSnapshot<T>.withData(ConnectionState.active, event);
      },
      onError: (error, stackTrace) {
        _snapshotNotifier.value = AsyncSnapshot<T>.withError(
            ConnectionState.active, error, stackTrace);
        if (!widget.silent) {
          widget.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              context:
                  ErrorDescription('While updating stream in AsyncBuilder'),
            ),
          );
        }
      },
      onDone: () {
        _snapshotNotifier.value = AsyncSnapshot<T>.withData(
            ConnectionState.done,
            _snapshotNotifier.value.data ??
                (throw ArgumentError(
                    "_snapshotNotifier.value.data must not be null")));
      },
    );
  }

  void _updatePause() {
    if (_subscription != null) {
      if (widget.pause && !_subscription!.isPaused) {
        _subscription!.pause();
      } else if (!widget.pause && _subscription!.isPaused) {
        _subscription!.resume();
      }
    }
  }

  void _cancel() {
    _subscription?.cancel();
    _subscription = null;
    if (!widget.retain) {
      _snapshotNotifier.value = AsyncSnapshot<T>.withData(
          ConnectionState.none,
          widget.initial ??
              (throw ArgumentError("widget.initial must not be null")));
    }
  }

  @override
  void didUpdateWidget(covariant JuiceAsyncBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.future != null) {
      if (widget.future != oldWidget.future) {
        _initFuture();
      }
    } else if (widget.stream != null) {
      if (widget.stream != oldWidget.stream) {
        _initStream();
      }
    } else {
      _cancel();
    }

    _updatePause();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ValueListenableBuilder<AsyncSnapshot<T>>(
      valueListenable: _snapshotNotifier,
      builder: (context, snapshot, child) {
        // Use the default `StreamStatus.initial` if snapshot.data is null
        T status = (snapshot.data ?? widget.initial) as T;

        if (snapshot.hasError && widget.error != null) {
          return widget.error!(
            context,
            status,
            snapshot.error!,
            snapshot.stackTrace,
          );
        }

        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null &&
            widget.closed != null) {
          return widget.closed!(context, status);
        }

        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data != null &&
            widget.waiting != null) {
          return widget.waiting!(context, status);
        }

        return widget.builder(context, status);
      },
    );
  }

  @override
  void dispose() {
    _cancel();
    _snapshotNotifier.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;
}
