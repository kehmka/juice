import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

/// Base class for creating stateless widgets that reactively respond to Juice bloc state changes.
///
/// StatelessJuiceWidget provides a structured way to build widgets that depend on a single bloc's state,
/// with support for selective rebuilding through groups and lifecycle management.
///
/// Type Parameters:
/// * [TBloc] - The type of bloc this widget observes
///
/// Example:
/// ```dart
/// class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
///   CounterDisplay({super.key, super.groups = const {"counter"}});
///
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) {
///     return Text(
///       'Count: ${bloc.state.count}',
///       style: Theme.of(context).textTheme.headline4,
///     );
///   }
/// }
/// ```
abstract class StatelessJuiceWidget<TBloc extends JuiceBloc>
    extends StatelessWidget {
  /// Creates a StatelessJuiceWidget with optional resolver and rebuild groups.
  ///
  /// [key] - Optional widget key, defaults to a new GlobalKey
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  StatelessJuiceWidget(
      {Key? key, BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : resolver = resolver ?? GlobalBlocResolver().resolver,
        super(key: key ?? GlobalKey());

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances
  final BlocDependencyResolver resolver;

  /// The bloc instance this widget observes.
  /// Resolved lazily when first accessed.
  @protected
  TBloc get bloc => resolver.resolve<TBloc>();

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      stream: bloc.stream.where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      initial: bloc.currentStatus,
      initiator: onInit,
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (context, status, o, ex) => _process(context, status),
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
  @protected
  bool onStateChange(StreamStatus status) => true;

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

abstract class StatelessJuiceWidget2<TBloc1 extends JuiceBloc,
    TBloc2 extends JuiceBloc> extends StatelessWidget {
  /// Creates a widget that observes two blocs for state changes.
  ///
  /// [key] - Optional widget key.
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  StatelessJuiceWidget2(
      {Key? key, BlocDependencyResolver? resolver, this.groups = const {}})
      : resolver = resolver ?? GlobalBlocResolver().resolver,
        super(key: key ?? GlobalKey());

  /// Groups that control when this widget rebuilds.
  /// Default is an empty set, meaning rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances.
  final BlocDependencyResolver resolver;

  /// First bloc instance observed by this widget.
  @protected
  TBloc1 get bloc1 => resolver.resolve<TBloc1>();

  /// Second bloc instance observed by this widget.
  @protected
  TBloc2 get bloc2 => resolver.resolve<TBloc2>();

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: bloc1.currentStatus,
      initiator: onInit,
      // Combines streams from both blocs.
      stream: MergeStream<StreamStatus>([bloc1.stream, bloc2.stream])
          .where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (context, status, o, ex) => _process(context, status),
      closed: (context, value) => close(context),
    );
  }

  /// Internal method to process state changes and safely call [onBuild].
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
  /// Override to add custom initialization logic.
  @protected
  void onInit() {}

  /// Called for each state change to determine if the widget should rebuild.
  /// Return false to prevent rebuild for a specific state change.
  @protected
  bool onStateChange(StreamStatus status) => true;

  /// Main build method to override. Constructs widget UI based on current status.
  @protected
  Widget onBuild(BuildContext context, StreamStatus status) {
    return const SizedBox.shrink();
  }

  /// Called when the bloc streams are closed.
  /// Override to handle cleanup or show a final UI state.
  @protected
  Widget close(BuildContext context) {
    return const SizedBox.shrink();
  }
}

abstract class StatelessJuiceWidget3<
    TBloc1 extends JuiceBloc,
    TBloc2 extends JuiceBloc,
    TBloc3 extends JuiceBloc> extends StatelessWidget {
  /// Creates a widget that observes three blocs for state changes.
  ///
  /// [key] - Optional widget key.
  /// [resolver] - Optional custom bloc resolver, defaults to global resolver.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  StatelessJuiceWidget3(
      {Key? key, BlocDependencyResolver? resolver, this.groups = const {"*"}})
      : resolver = resolver ?? GlobalBlocResolver().resolver,
        super(key: key ?? GlobalKey());

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  final Set<String> groups;

  /// Resolver used to obtain bloc instances.
  final BlocDependencyResolver resolver;

  /// First bloc instance observed by this widget.
  @protected
  TBloc1 get bloc1 => resolver.resolve<TBloc1>();

  /// Second bloc instance observed by this widget.
  @protected
  TBloc2 get bloc2 => resolver.resolve<TBloc2>();

  /// Third bloc instance observed by this widget.
  @protected
  TBloc3 get bloc3 => resolver.resolve<TBloc3>();

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: bloc1.currentStatus,
      initiator: onInit,
      // Combines streams from all three blocs.
      stream:
          MergeStream<StreamStatus>([bloc1.stream, bloc2.stream, bloc3.stream])
              .where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _process(context, status),
      builder: (context, status) => _process(context, status),
      error: (c, status, o, s) => _process(context, status),
      closed: (context, value) => close(context),
    );
  }

  /// Internal method to process state changes and safely call [onBuild].
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
  /// Override to add custom initialization logic.
  @protected
  void onInit() {}

  /// Called for each state change to determine if the widget should rebuild.
  /// Return false to prevent rebuild for a specific state change.
  @protected
  bool onStateChange(StreamStatus status) => true;

  /// Main build method to override. Constructs widget UI based on current status.
  @protected
  Widget onBuild(BuildContext context, StreamStatus status) {
    return const SizedBox.shrink();
  }

  /// Called when the bloc streams are closed.
  /// Override to handle cleanup or show a final UI state.
  @protected
  Widget close(BuildContext context) {
    return const SizedBox.shrink();
  }
}
