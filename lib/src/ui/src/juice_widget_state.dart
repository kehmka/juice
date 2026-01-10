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
class JuiceWidgetState<TBloc extends JuiceBloc, TWidget extends StatefulWidget>
    extends State<TWidget> {
  /// Creates a JuiceWidgetState with optional dependency resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instance
  TBloc? _bloc;

  /// Lease for lifecycle management when using BlocScope
  BlocLease<TBloc>? _lease;

  /// The bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc get bloc {
    if (_bloc != null) return _bloc!;

    if (_customResolver != null) {
      // Legacy path: use custom resolver directly
      _bloc = _customResolver.resolve<TBloc>();
    } else {
      // New path: use BlocScope with lease for proper lifecycle management
      _lease = BlocScope.lease<TBloc>();
      _bloc = _lease!.bloc;
    }
    return _bloc!;
  }

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: bloc.currentStatus,
      initiator: onInit,
      stream: bloc.stream.where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        if (!onStateChange(status)) return false;
        prepareForUpdate(status);
        if (mounted) setState(() {});
        return true;
      }),
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (c, status, o, s) => _build(context, status),
      closed: (context, value) => close(context),
    );
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

  /// Called before setState when a state change is accepted.
  /// Override to prepare widget for upcoming state change.
  ///
  /// This is called after [onStateChange] returns true and before the widget rebuilds.
  /// Use this to perform any necessary preparations for the state update.
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
    // Release the lease if we acquired one
    _lease?.dispose();
    _lease = null;
    _bloc = null;
    super.dispose();
  }
}

/// Base class for creating stateful widgets that respond to two Juice blocs.
///
/// Similar to JuiceWidgetState but handles state changes from two different blocs,
/// merging their streams and providing access to both bloc instances.
class JuiceWidgetState2<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc,
    TWidget extends StatefulWidget> extends State<TWidget> {
  /// Creates a JuiceWidgetState2 with optional resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState2(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instances
  TBloc1? _bloc1;
  TBloc2? _bloc2;

  /// Leases for lifecycle management when using BlocScope
  BlocLease<TBloc1>? _lease1;
  BlocLease<TBloc2>? _lease2;

  /// The first bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc1 get bloc1 {
    if (_bloc1 != null) return _bloc1!;

    if (_customResolver != null) {
      _bloc1 = _customResolver.resolve<TBloc1>();
    } else {
      _lease1 = BlocScope.lease<TBloc1>();
      _bloc1 = _lease1!.bloc;
    }
    return _bloc1!;
  }

  /// The second bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc2 get bloc2 {
    if (_bloc2 != null) return _bloc2!;

    if (_customResolver != null) {
      _bloc2 = _customResolver.resolve<TBloc2>();
    } else {
      _lease2 = BlocScope.lease<TBloc2>();
      _bloc2 = _lease2!.bloc;
    }
    return _bloc2!;
  }

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: bloc1.currentStatus,
      initiator: onInit,
      stream: MergeStream<StreamStatus>([bloc1.stream, bloc2.stream])
          .where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        if (!onStateChange(status)) return false;
        prepareForUpdate(status);
        if (mounted) setState(() {});
        return true;
      }),
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (c, status, o, s) => _build(context, status),
      closed: (context, value) => close(context),
    );
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

  /// Called before setState when a state change is accepted.
  /// Override to prepare widget for upcoming state change.
  ///
  /// This is called when either bloc emits a new state.
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
    // Release the leases if we acquired them
    _lease1?.dispose();
    _lease2?.dispose();
    _lease1 = null;
    _lease2 = null;
    _bloc1 = null;
    _bloc2 = null;
    super.dispose();
  }
}

/// Base class for creating stateful widgets that respond to three Juice blocs.
///
/// Similar to JuiceWidgetState but handles state changes from three different blocs,
/// merging their streams and providing access to all bloc instances.
class JuiceWidgetState3<
    TBloc1 extends JuiceBloc,
    TBloc2 extends JuiceBloc,
    TBloc3 extends JuiceBloc,
    TWidget extends StatefulWidget> extends State<TWidget> {
  /// Creates a JuiceWidgetState3 with optional resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState3(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// Cached bloc instances
  TBloc1? _bloc1;
  TBloc2? _bloc2;
  TBloc3? _bloc3;

  /// Leases for lifecycle management when using BlocScope
  BlocLease<TBloc1>? _lease1;
  BlocLease<TBloc2>? _lease2;
  BlocLease<TBloc3>? _lease3;

  /// The first bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc1 get bloc1 {
    if (_bloc1 != null) return _bloc1!;

    if (_customResolver != null) {
      _bloc1 = _customResolver.resolve<TBloc1>();
    } else {
      _lease1 = BlocScope.lease<TBloc1>();
      _bloc1 = _lease1!.bloc;
    }
    return _bloc1!;
  }

  /// The second bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc2 get bloc2 {
    if (_bloc2 != null) return _bloc2!;

    if (_customResolver != null) {
      _bloc2 = _customResolver.resolve<TBloc2>();
    } else {
      _lease2 = BlocScope.lease<TBloc2>();
      _bloc2 = _lease2!.bloc;
    }
    return _bloc2!;
  }

  /// The third bloc instance this widget observes.
  /// Resolved via BlocScope or custom resolver.
  TBloc3 get bloc3 {
    if (_bloc3 != null) return _bloc3!;

    if (_customResolver != null) {
      _bloc3 = _customResolver.resolve<TBloc3>();
    } else {
      _lease3 = BlocScope.lease<TBloc3>();
      _bloc3 = _lease3!.bloc;
    }
    return _bloc3!;
  }

  @override
  @protected
  @mustCallSuper
  void initState() {
    super.initState();
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: bloc1.currentStatus,
      initiator: onInit,
      stream:
          MergeStream<StreamStatus>([bloc1.stream, bloc2.stream, bloc3.stream])
              .where((status) {
        if (denyRebuild(
            event: status.event, key: widget.key, rebuildGroups: groups)) {
          return false;
        }
        if (!onStateChange(status)) return false;
        prepareForUpdate(status);
        if (mounted) setState(() {});
        return true;
      }),
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (c, status, o, s) => _build(context, status),
      closed: (context, value) => close(context),
    );
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

  /// Called before setState when a state change is accepted.
  /// Override to prepare widget for upcoming state change.
  ///
  /// This is called when any of the three blocs emits a new state.
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
    // Release the leases if we acquired them
    _lease1?.dispose();
    _lease2?.dispose();
    _lease3?.dispose();
    _lease1 = null;
    _lease2 = null;
    _lease3 = null;
    _bloc1 = null;
    _bloc2 = null;
    _bloc3 = null;
    super.dispose();
  }
}
