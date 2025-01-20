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
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : resolver = resolver ?? GlobalBlocResolver().resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances
  final BlocDependencyResolver resolver;

  /// The bloc instance this widget observes
  TBloc get bloc => resolver.resolve<TBloc>();

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
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (c, status, o, s) => _process(context, status),
      closed: (context, value) => close(context),
    );
  }

  /// Internal method to process build requests with error handling.
  /// Wraps onBuild with try-catch and converts errors to JuiceExceptionWidget.
  Widget _process(BuildContext context, StreamStatus status) {
    try {
      return onBuild(context, status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
          exception: error is Exception ? error : Exception(error),
          stackTrace: stackTrace);
    }
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
}

/// Base class for creating stateful widgets that respond to two Juice blocs.
///
/// Similar to JuiceWidgetState but handles state changes from two different blocs,
/// merging their streams and providing access to both bloc instances.
class JuiceWidgetState2<TBloc1 extends JuiceBloc, TBloc2 extends JuiceBloc,
    TWidget extends StatefulWidget> extends State<TWidget> {
  /// Creates a JuiceWidgetState2 with optional resolver and rebuild groups.
  ///
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState2(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : resolver = resolver ?? GlobalBlocResolver().resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances
  final BlocDependencyResolver resolver;

  /// The first bloc instance this widget observes
  TBloc1 get bloc1 => resolver.resolve<TBloc1>();

  /// The second bloc instance this widget observes
  TBloc2 get bloc2 => resolver.resolve<TBloc2>();

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
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (c, status, o, s) => _process(context, status),
      closed: (context, value) => close(context),
    );
  }

  Widget _process(BuildContext context, StreamStatus status) {
    try {
      return onBuild(context, status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
          exception: error is Exception ? error : Exception(error),
          stackTrace: stackTrace);
    }
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
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  JuiceWidgetState3(
      {BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : resolver = resolver ?? GlobalBlocResolver().resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances
  final BlocDependencyResolver resolver;

  /// The first bloc instance this widget observes
  TBloc1 get bloc1 => resolver.resolve<TBloc1>();

  /// The second bloc instance this widget observes
  TBloc2 get bloc2 => resolver.resolve<TBloc2>();

  /// The third bloc instance this widget observes
  TBloc3 get bloc3 => resolver.resolve<TBloc3>();

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
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (c, status, o, s) => _process(context, status),
      closed: (context, value) => close(context),
    );
  }

  Widget _process(BuildContext context, StreamStatus status) {
    try {
      return onBuild(context, status);
    } catch (error, stackTrace) {
      return JuiceExceptionWidget(
          exception: error is Exception ? error : Exception(error),
          stackTrace: stackTrace);
    }
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
}
