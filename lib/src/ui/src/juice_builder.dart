import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

/// A builder widget that reactively rebuilds in response to bloc state changes.
///
/// JuiceBuilder provides a composable way to build widgets that depend on a
/// bloc's state, without requiring inheritance. It can be used inline anywhere
/// in the widget tree.
///
/// Example:
/// ```dart
/// JuiceBuilder<CounterBloc>(
///   groups: {'counter'},
///   builder: (context, bloc, status) {
///     return Text('Count: ${bloc.state.count}');
///   },
/// )
/// ```
///
/// For conditional rebuilding, use [buildWhen]:
/// ```dart
/// JuiceBuilder<CounterBloc>(
///   buildWhen: (status) => bloc.state.count.isEven,
///   builder: (context, bloc, status) {
///     return Text('Even count: ${bloc.state.count}');
///   },
/// )
/// ```
class JuiceBuilder<TBloc extends JuiceBloc> extends StatefulWidget {
  /// Creates a JuiceBuilder.
  ///
  /// [builder] is called whenever the bloc emits a new state that passes
  /// the rebuild filters.
  ///
  /// [groups] controls which rebuild groups this widget responds to.
  /// Defaults to `{'*'}` which rebuilds on all state changes.
  ///
  /// [buildWhen] is an optional additional filter. Return false to skip
  /// rebuilding for a particular state change.
  ///
  /// [resolver] optionally provides a custom bloc resolver. Defaults to
  /// the global resolver.
  const JuiceBuilder({
    super.key,
    required this.builder,
    this.groups = const {'*'},
    this.buildWhen,
    this.resolver,
    this.onInit,
    this.onDispose,
  });

  /// Builds the widget based on the current bloc state.
  final Widget Function(BuildContext context, TBloc bloc, StreamStatus status) builder;

  /// Groups that control when this widget rebuilds.
  /// Default is `{'*'}` which means rebuild on all state changes.
  final Set<String> groups;

  /// Optional condition to determine if the widget should rebuild.
  /// Return false to skip rebuilding for a state change.
  final bool Function(StreamStatus status)? buildWhen;

  /// Optional custom bloc resolver. Defaults to global resolver.
  final BlocDependencyResolver? resolver;

  /// Called when the widget is first initialized.
  final VoidCallback? onInit;

  /// Called when the widget is disposed.
  final VoidCallback? onDispose;

  @override
  State<JuiceBuilder<TBloc>> createState() => _JuiceBuilderState<TBloc>();
}

class _JuiceBuilderState<TBloc extends JuiceBloc>
    extends State<JuiceBuilder<TBloc>> {
  late final TBloc _bloc;
  late StreamStatus _status;
  StreamSubscription<StreamStatus>? _subscription;
  BlocLease<TBloc>? _lease;

  @override
  void initState() {
    super.initState();
    if (widget.resolver != null) {
      // Legacy path: use custom resolver directly
      _bloc = widget.resolver!.resolve<TBloc>();
    } else {
      // New path: use BlocScope with lease for proper lifecycle management
      _lease = BlocScope.lease<TBloc>();
      _bloc = _lease!.bloc;
    }
    _status = _bloc.currentStatus;
    _subscribe();
    widget.onInit?.call();
  }

  void _subscribe() {
    _subscription = _bloc.stream.where(_shouldRebuild).listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
  }

  bool _shouldRebuild(StreamStatus status) {
    // Check rebuild groups
    if (denyRebuild(
      event: status.event,
      key: widget.key,
      rebuildGroups: widget.groups,
    )) {
      return false;
    }

    // Check custom buildWhen condition
    if (widget.buildWhen != null && !widget.buildWhen!(status)) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _lease?.dispose();
    _lease = null;
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return widget.builder(context, _bloc, _status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
        exception: error is Exception ? error : Exception(error.toString()),
        stackTrace: stackTrace,
      );
    }
  }
}

/// A builder widget that reactively rebuilds in response to two blocs' state changes.
///
/// Example:
/// ```dart
/// JuiceBuilder2<CounterBloc, SettingsBloc>(
///   groups: {'counter', 'theme'},
///   builder: (context, counterBloc, settingsBloc, status) {
///     return Text(
///       'Count: ${counterBloc.state.count}',
///       style: TextStyle(
///         color: settingsBloc.state.isDarkMode ? Colors.white : Colors.black,
///       ),
///     );
///   },
/// )
/// ```
class JuiceBuilder2<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc>
    extends StatefulWidget {
  const JuiceBuilder2({
    super.key,
    required this.builder,
    this.groups = const {'*'},
    this.buildWhen,
    this.resolver,
    this.onInit,
    this.onDispose,
  });

  /// Builds the widget based on the current bloc states.
  final Widget Function(
    BuildContext context,
    TBloc1 bloc1,
    TBloc2 bloc2,
    StreamStatus status,
  ) builder;

  /// Groups that control when this widget rebuilds.
  final Set<String> groups;

  /// Optional condition to determine if the widget should rebuild.
  final bool Function(StreamStatus status)? buildWhen;

  /// Optional custom bloc resolver.
  final BlocDependencyResolver? resolver;

  /// Called when the widget is first initialized.
  final VoidCallback? onInit;

  /// Called when the widget is disposed.
  final VoidCallback? onDispose;

  @override
  State<JuiceBuilder2<TBloc1, TBloc2>> createState() =>
      _JuiceBuilder2State<TBloc1, TBloc2>();
}

class _JuiceBuilder2State<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc>
    extends State<JuiceBuilder2<TBloc1, TBloc2>> {
  late final TBloc1 _bloc1;
  late final TBloc2 _bloc2;
  late StreamStatus _status;
  StreamSubscription<StreamStatus>? _subscription;
  BlocLease<TBloc1>? _lease1;
  BlocLease<TBloc2>? _lease2;

  @override
  void initState() {
    super.initState();
    if (widget.resolver != null) {
      // Legacy path: use custom resolver directly
      _bloc1 = widget.resolver!.resolve<TBloc1>();
      _bloc2 = widget.resolver!.resolve<TBloc2>();
    } else {
      // New path: use BlocScope with lease for proper lifecycle management
      _lease1 = BlocScope.lease<TBloc1>();
      _lease2 = BlocScope.lease<TBloc2>();
      _bloc1 = _lease1!.bloc;
      _bloc2 = _lease2!.bloc;
    }
    _status = _bloc1.currentStatus;
    _subscribe();
    widget.onInit?.call();
  }

  void _subscribe() {
    final merged = MergeStream<StreamStatus>([_bloc1.stream, _bloc2.stream]);
    _subscription = merged.where(_shouldRebuild).listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
  }

  bool _shouldRebuild(StreamStatus status) {
    if (denyRebuild(
      event: status.event,
      key: widget.key,
      rebuildGroups: widget.groups,
    )) {
      return false;
    }

    if (widget.buildWhen != null && !widget.buildWhen!(status)) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _lease1?.dispose();
    _lease1 = null;
    _lease2?.dispose();
    _lease2 = null;
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return widget.builder(context, _bloc1, _bloc2, _status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
        exception: error is Exception ? error : Exception(error.toString()),
        stackTrace: stackTrace,
      );
    }
  }
}

/// A builder widget that reactively rebuilds in response to multiple blocs' state changes.
///
/// Use this when you need to observe more than 2 blocs, or when the number
/// of blocs is dynamic.
///
/// Example:
/// ```dart
/// JuiceMultiBuilder(
///   blocs: [counterBloc, settingsBloc, userBloc],
///   groups: {'counter', 'settings', 'user'},
///   builder: (context, statuses) {
///     return Text('Observing ${statuses.length} blocs');
///   },
/// )
/// ```
///
/// For type-safe access to specific blocs, resolve them separately:
/// ```dart
/// JuiceMultiBuilder(
///   resolve: (resolver) => [
///     resolver.resolve<CounterBloc>(),
///     resolver.resolve<SettingsBloc>(),
///     resolver.resolve<UserBloc>(),
///   ],
///   builder: (context, blocs, status) {
///     final counter = blocs[0] as CounterBloc;
///     final settings = blocs[1] as SettingsBloc;
///     final user = blocs[2] as UserBloc;
///     return Text('${counter.state.count}');
///   },
/// )
/// ```
class JuiceMultiBuilder extends StatefulWidget {
  /// Creates a JuiceMultiBuilder with explicit bloc instances.
  const JuiceMultiBuilder({
    super.key,
    required this.blocs,
    required this.builder,
    this.groups = const {'*'},
    this.buildWhen,
    this.onInit,
    this.onDispose,
  }) : resolve = null;

  /// Creates a JuiceMultiBuilder that resolves blocs from the resolver.
  const JuiceMultiBuilder.resolve({
    super.key,
    required List<JuiceBloc> Function(BlocDependencyResolver resolver) this.resolve,
    required this.builder,
    this.groups = const {'*'},
    this.buildWhen,
    this.onInit,
    this.onDispose,
  }) : blocs = const [];

  /// Explicit list of blocs to observe.
  final List<JuiceBloc> blocs;

  /// Function to resolve blocs from the dependency resolver.
  final List<JuiceBloc> Function(BlocDependencyResolver resolver)? resolve;

  /// Builds the widget based on the current bloc states.
  final Widget Function(
    BuildContext context,
    List<JuiceBloc> blocs,
    StreamStatus status,
  ) builder;

  /// Groups that control when this widget rebuilds.
  final Set<String> groups;

  /// Optional condition to determine if the widget should rebuild.
  final bool Function(StreamStatus status)? buildWhen;

  /// Called when the widget is first initialized.
  final VoidCallback? onInit;

  /// Called when the widget is disposed.
  final VoidCallback? onDispose;

  @override
  State<JuiceMultiBuilder> createState() => _JuiceMultiBuilderState();
}

class _JuiceMultiBuilderState extends State<JuiceMultiBuilder> {
  late final List<JuiceBloc> _blocs;
  late StreamStatus _status;
  StreamSubscription<StreamStatus>? _subscription;
  final List<BlocLease> _leases = [];

  @override
  void initState() {
    super.initState();

    if (widget.resolve != null) {
      // Use a lease-tracking resolver
      final resolver = _LeaseTrackingResolver(_leases);
      _blocs = widget.resolve!(resolver);
    } else {
      _blocs = widget.blocs;
    }

    if (_blocs.isEmpty) {
      throw StateError('JuiceMultiBuilder requires at least one bloc');
    }

    _status = _blocs.first.currentStatus;
    _subscribe();
    widget.onInit?.call();
  }

  void _subscribe() {
    final streams = _blocs.map((b) => b.stream).toList();
    final merged = MergeStream<StreamStatus>(streams);
    _subscription = merged.where(_shouldRebuild).listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
  }

  bool _shouldRebuild(StreamStatus status) {
    if (denyRebuild(
      event: status.event,
      key: widget.key,
      rebuildGroups: widget.groups,
    )) {
      return false;
    }

    if (widget.buildWhen != null && !widget.buildWhen!(status)) {
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final lease in _leases) {
      lease.dispose();
    }
    _leases.clear();
    widget.onDispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      return widget.builder(context, _blocs, _status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
        exception: error is Exception ? error : Exception(error.toString()),
        stackTrace: stackTrace,
      );
    }
  }
}

/// Internal resolver that tracks leases for proper lifecycle management.
class _LeaseTrackingResolver implements BlocDependencyResolver {
  _LeaseTrackingResolver(this._leases);

  final List<BlocLease> _leases;

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    final lease = BlocScope.lease<T>();
    _leases.add(lease);
    return lease.bloc;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final blocLease = BlocScope.lease<T>(scope: scope);
    _leases.add(blocLease);
    return blocLease;
  }

  @override
  Future<void> disposeAll() async {
    for (final lease in _leases) {
      lease.dispose();
    }
    _leases.clear();
  }
}
