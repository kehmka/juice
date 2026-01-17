import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

/// Base class for creating stateful widgets that reactively respond to Juice bloc state changes.
///
/// JuiceWidgetState manages the connection between a stateful widget and a bloc,
/// providing a structured way to handle state changes, control widget rebuilds,
/// and manage widget lifecycle.
///
/// Type Parameters:
/// * [TBloc] - The type of bloc this widget observes
/// * [TWidget] - The type of the stateful widget
///
/// Example usage:
/// ```dart
/// class MyWidget extends StatefulWidget {
///   @override
///   State<MyWidget> createState() => MyWidgetState();
/// }
///
/// class MyWidgetState extends JuiceWidgetState<MyBloc, MyWidget> {
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) {
///     return Column(
///       children: [
///         Text(bloc.state.data),
///         if (status is Waiting)
///           CircularProgressIndicator(),
///       ],
///     );
///   }
/// }
/// ```
abstract class JuiceWidgetState<TBloc extends JuiceBloc<BlocState>,
    TWidget extends StatefulWidget> extends State<TWidget> {
  /// Creates a JuiceWidgetState with optional dependency resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  ///   Note: When using a custom resolver, the bloc lifecycle is not managed
  ///   (no lease/dispose). The resolver is responsible for bloc lifecycle.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  /// [scope] - Optional scope key for resolving scoped bloc instances.
  JuiceWidgetState({
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve immutability.
  final Set<String> groups;

  /// Optional scope key for resolving scoped bloc instances.
  final Object? scope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instance, initialized in initState.
  late final TBloc _bloc;

  /// Lease for lifecycle management when using BlocScope.
  BlocLease<TBloc>? _lease;

  /// Tracks last status to only call prepareForUpdate on actual changes.
  StreamStatus? _lastStatus;

  /// The bloc instance this widget observes.
  TBloc get bloc => _bloc;

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
    if (_customResolver != null) {
      _bloc = _customResolver.resolve<TBloc>();
    } else {
      _lease = BlocScope.lease<TBloc>(scope: scope);
      _bloc = _lease!.bloc;
    }
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: _bloc.currentStatus,
      initiator: onInit,
      stream: _bloc.stream.where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _buildWithPrep(context, status),
      builder: (context, status) => _buildWithPrep(context, status),
      error: (c, status, o, s) => _buildWithPrep(context, status),
      closed: (context, value) => close(context),
    );
  }

  Widget _buildWithPrep(BuildContext context, StreamStatus status) {
    if (!identical(_lastStatus, status)) {
      _lastStatus = status;
      prepareForUpdate(status);
    }
    return _build(context, status);
  }

  Widget _build(BuildContext context, StreamStatus status) {
    return JuiceWidgetSupport.processWithErrorHandling(
      context: context,
      status: status,
      onBuild: onBuild,
    );
  }

  /// Called when the widget is first initialized.
  /// Override to add initialization logic.
  @protected
  void onInit() {}

  /// Called for each state change to determine if widget should rebuild.
  /// Return false to prevent rebuild for this state change.
  ///
  /// This is the first level of rebuild control, before [prepareForUpdate].
  /// Use this to filter out unwanted state changes.
  @protected
  bool onStateChange(StreamStatus status) => true;

  /// Called when the stream emits a new status that passed [onStateChange].
  /// Override to prepare widget for the upcoming rebuild.
  ///
  /// Only called when status actually changes (not on parent rebuilds).
  @protected
  void prepareForUpdate(StreamStatus status) {}

  /// Main build method to override. Constructs widget UI based on current status.
  ///
  /// This is where you implement your widget's UI. The method receives the current
  /// [StreamStatus] which can be used to show different UI states (loading, error, etc).
  @protected
  Widget onBuild(BuildContext context, StreamStatus status) {
    return const SizedBox.shrink();
  }

  /// Called when the bloc stream is closed.
  /// Override to handle cleanup or show final UI state.
  @protected
  Widget close(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _lease?.dispose();
    super.dispose();
  }
}

/// Base class for creating stateful widgets that respond to two Juice blocs.
///
/// Similar to JuiceWidgetState but handles state changes from two different blocs,
/// merging their streams and providing access to both bloc instances.
abstract class JuiceWidgetState2<TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>, TWidget extends StatefulWidget>
    extends State<TWidget> {
  /// Creates a JuiceWidgetState2 with optional resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  ///   Note: When using a custom resolver, the bloc lifecycle is not managed
  ///   (no lease/dispose). The resolver is responsible for bloc lifecycle.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  /// [scope1] - Optional scope key for first bloc.
  /// [scope2] - Optional scope key for second bloc.
  JuiceWidgetState2({
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope1,
    this.scope2,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve immutability.
  final Set<String> groups;

  /// Optional scope keys for blocs.
  final Object? scope1;
  final Object? scope2;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instances, initialized in initState.
  late final TBloc1 _bloc1;
  late final TBloc2 _bloc2;

  /// Leases for lifecycle management when using BlocScope.
  BlocLease<TBloc1>? _lease1;
  BlocLease<TBloc2>? _lease2;

  /// Tracks last status to only call prepareForUpdate on actual changes.
  StreamStatus? _lastStatus;

  /// The first bloc instance this widget observes.
  TBloc1 get bloc1 => _bloc1;

  /// The second bloc instance this widget observes.
  TBloc2 get bloc2 => _bloc2;

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
    if (_customResolver != null) {
      _bloc1 = _customResolver.resolve<TBloc1>();
      _bloc2 = _customResolver.resolve<TBloc2>();
    } else {
      _lease1 = BlocScope.lease<TBloc1>(scope: scope1);
      _lease2 = BlocScope.lease<TBloc2>(scope: scope2);
      _bloc1 = _lease1!.bloc;
      _bloc2 = _lease2!.bloc;
    }
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: _bloc1.currentStatus,
      initiator: onInit,
      stream: MergeStream<StreamStatus>([_bloc1.stream, _bloc2.stream])
          .where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _buildWithPrep(context, status),
      builder: (context, status) => _buildWithPrep(context, status),
      error: (c, status, o, s) => _buildWithPrep(context, status),
      closed: (context, value) => close(context),
    );
  }

  Widget _buildWithPrep(BuildContext context, StreamStatus status) {
    if (!identical(_lastStatus, status)) {
      _lastStatus = status;
      prepareForUpdate(status);
    }
    return _build(context, status);
  }

  Widget _build(BuildContext context, StreamStatus status) {
    return JuiceWidgetSupport.processWithErrorHandling(
      context: context,
      status: status,
      onBuild: onBuild,
    );
  }

  /// Called when the widget is first initialized.
  /// Override to add initialization logic.
  @protected
  void onInit() {}

  /// Called for each state change to determine if widget should rebuild.
  /// Return false to prevent rebuild for this state change.
  ///
  /// This is called for state changes from either bloc.
  @protected
  bool onStateChange(StreamStatus status) => true;

  /// Called when the merged stream emits a new status that passed [onStateChange].
  /// Override to prepare widget for the upcoming rebuild.
  ///
  /// Only called when status actually changes (not on parent rebuilds).
  @protected
  void prepareForUpdate(StreamStatus status) {}

  /// Main build method to override. Constructs widget UI based on current status.
  ///
  /// Access both blocs through bloc1 and bloc2 properties.
  @protected
  Widget onBuild(BuildContext context, StreamStatus status) {
    return const SizedBox.shrink();
  }

  /// Called when either bloc stream is closed.
  /// Override to handle cleanup or show final UI state.
  @protected
  Widget close(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _lease1?.dispose();
    _lease2?.dispose();
    super.dispose();
  }
}

/// Base class for creating stateful widgets that respond to three Juice blocs.
///
/// Similar to JuiceWidgetState but handles state changes from three different blocs,
/// merging their streams and providing access to all bloc instances.
abstract class JuiceWidgetState3<
    TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>,
    TBloc3 extends JuiceBloc<BlocState>,
    TWidget extends StatefulWidget> extends State<TWidget> {
  /// Creates a JuiceWidgetState3 with optional resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  ///   Note: When using a custom resolver, the bloc lifecycle is not managed
  ///   (no lease/dispose). The resolver is responsible for bloc lifecycle.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  /// [scope1] - Optional scope key for first bloc.
  /// [scope2] - Optional scope key for second bloc.
  /// [scope3] - Optional scope key for third bloc.
  JuiceWidgetState3({
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope1,
    this.scope2,
    this.scope3,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve immutability.
  final Set<String> groups;

  /// Optional scope keys for blocs.
  final Object? scope1;
  final Object? scope2;
  final Object? scope3;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instances, initialized in initState.
  late final TBloc1 _bloc1;
  late final TBloc2 _bloc2;
  late final TBloc3 _bloc3;

  /// Leases for lifecycle management when using BlocScope.
  BlocLease<TBloc1>? _lease1;
  BlocLease<TBloc2>? _lease2;
  BlocLease<TBloc3>? _lease3;

  /// Tracks last status to only call prepareForUpdate on actual changes.
  StreamStatus? _lastStatus;

  /// The first bloc instance this widget observes.
  TBloc1 get bloc1 => _bloc1;

  /// The second bloc instance this widget observes.
  TBloc2 get bloc2 => _bloc2;

  /// The third bloc instance this widget observes.
  TBloc3 get bloc3 => _bloc3;

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
    if (_customResolver != null) {
      _bloc1 = _customResolver.resolve<TBloc1>();
      _bloc2 = _customResolver.resolve<TBloc2>();
      _bloc3 = _customResolver.resolve<TBloc3>();
    } else {
      _lease1 = BlocScope.lease<TBloc1>(scope: scope1);
      _lease2 = BlocScope.lease<TBloc2>(scope: scope2);
      _lease3 = BlocScope.lease<TBloc3>(scope: scope3);
      _bloc1 = _lease1!.bloc;
      _bloc2 = _lease2!.bloc;
      _bloc3 = _lease3!.bloc;
    }
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: _bloc1.currentStatus,
      initiator: onInit,
      stream: MergeStream<StreamStatus>(
              [_bloc1.stream, _bloc2.stream, _bloc3.stream])
          .where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _buildWithPrep(context, status),
      builder: (context, status) => _buildWithPrep(context, status),
      error: (c, status, o, s) => _buildWithPrep(context, status),
      closed: (context, value) => close(context),
    );
  }

  Widget _buildWithPrep(BuildContext context, StreamStatus status) {
    if (!identical(_lastStatus, status)) {
      _lastStatus = status;
      prepareForUpdate(status);
    }
    return _build(context, status);
  }

  Widget _build(BuildContext context, StreamStatus status) {
    return JuiceWidgetSupport.processWithErrorHandling(
      context: context,
      status: status,
      onBuild: onBuild,
    );
  }

  /// Called when the widget is first initialized.
  /// Override to add initialization logic.
  @protected
  void onInit() {}

  /// Called for each state change to determine if widget should rebuild.
  /// Return false to prevent rebuild for this state change.
  ///
  /// This is called for state changes from any of the three blocs.
  @protected
  bool onStateChange(StreamStatus status) => true;

  /// Called when the merged stream emits a new status that passed [onStateChange].
  /// Override to prepare widget for the upcoming rebuild.
  ///
  /// Only called when status actually changes (not on parent rebuilds).
  @protected
  void prepareForUpdate(StreamStatus status) {}

  /// Main build method to override. Constructs widget UI based on current status.
  ///
  /// Access blocs through bloc1, bloc2, and bloc3 properties.
  @protected
  Widget onBuild(BuildContext context, StreamStatus status) {
    return const SizedBox.shrink();
  }

  /// Called when any bloc stream is closed.
  /// Override to handle cleanup or show final UI state.
  @protected
  Widget close(BuildContext context) {
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    _lease1?.dispose();
    _lease2?.dispose();
    _lease3?.dispose();
    super.dispose();
  }
}
