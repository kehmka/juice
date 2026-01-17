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
abstract class StatelessJuiceWidget<TBloc extends JuiceBloc<BlocState>>
    extends StatelessWidget {
  /// Creates a StatelessJuiceWidget with optional resolver and rebuild groups.
  ///
  /// [key] - Optional widget key
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds
  /// [scope] - Optional scope key for resolving scoped bloc instances
  ///
  /// Note: Do not access [bloc] in the widget constructor or field initializers.
  /// The bloc is only available after the lease holder has run in [build].
  StatelessJuiceWidget({
    super.key,
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve widget immutability.
  final Set<String> groups;

  /// Optional scope key for resolving scoped bloc instances.
  final Object? scope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// The bloc instance this widget observes.
  ///
  /// For legacy resolver path: resolved directly from resolver.
  /// For BlocScope path: accessed via peekExisting() after lease holder
  /// has ensured the instance exists.
  @protected
  TBloc get bloc {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc>();
    }
    return BlocScope.peekExisting<TBloc>(scope: scope);
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    if (_customResolver != null) {
      // Legacy path: resolve once and pass to builder
      final b = _customResolver.resolve<TBloc>();
      return _buildAsyncBuilder(b);
    }

    // New path: use BlocScope with lease holder for proper lifecycle management.
    // The lease holder ensures the bloc instance exists before building.
    return _BlocLeaseHolder<TBloc>(
      scope: scope,
      builder: (b) => _buildAsyncBuilder(b),
    );
  }

  Widget _buildAsyncBuilder(TBloc b) {
    return JuiceAsyncBuilder<StreamStatus>(
      stream: b.stream.where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      initial: b.currentStatus,
      initiator: onInit,
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (context, status, o, ex) => _build(context, status),
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

abstract class StatelessJuiceWidget2<TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>> extends StatelessWidget {
  /// Creates a widget that observes two blocs for state changes.
  ///
  /// [key] - Optional widget key.
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  /// [scope1] - Optional scope key for first bloc.
  /// [scope2] - Optional scope key for second bloc.
  ///
  /// Note: Do not access [bloc1] or [bloc2] in the widget constructor or field initializers.
  StatelessJuiceWidget2({
    super.key,
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope1,
    this.scope2,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve widget immutability.
  final Set<String> groups;

  /// Optional scope key for first bloc.
  final Object? scope1;

  /// Optional scope key for second bloc.
  final Object? scope2;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// First bloc instance observed by this widget.
  @protected
  TBloc1 get bloc1 {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc1>();
    }
    return BlocScope.peekExisting<TBloc1>(scope: scope1);
  }

  /// Second bloc instance observed by this widget.
  @protected
  TBloc2 get bloc2 {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc2>();
    }
    return BlocScope.peekExisting<TBloc2>(scope: scope2);
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    if (_customResolver != null) {
      // Legacy path: resolve once and pass to builder
      final b1 = _customResolver.resolve<TBloc1>();
      final b2 = _customResolver.resolve<TBloc2>();
      return _buildAsyncBuilder(b1, b2);
    }

    // New path: use BlocScope with lease holders
    return _BlocLeaseHolder2<TBloc1, TBloc2>(
      scope1: scope1,
      scope2: scope2,
      builder: (b1, b2) => _buildAsyncBuilder(b1, b2),
    );
  }

  Widget _buildAsyncBuilder(TBloc1 b1, TBloc2 b2) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: b1.currentStatus,
      initiator: onInit,
      stream: MergeStream<StreamStatus>([b1.stream, b2.stream]).where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (context, status, o, ex) => _build(context, status),
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
    TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>,
    TBloc3 extends JuiceBloc<BlocState>> extends StatelessWidget {
  /// Creates a widget that observes three blocs for state changes.
  ///
  /// [key] - Optional widget key.
  /// [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// [groups] - Set of rebuild group names that control when this widget rebuilds.
  /// [scope1] - Optional scope key for first bloc.
  /// [scope2] - Optional scope key for second bloc.
  /// [scope3] - Optional scope key for third bloc.
  ///
  /// Note: Do not access [bloc1], [bloc2], or [bloc3] in the widget constructor or field initializers.
  StatelessJuiceWidget3({
    super.key,
    BlocDependencyResolver? resolver,
    Set<String> groups = const {"*"},
    this.scope1,
    this.scope2,
    this.scope3,
  })  : groups = Set.unmodifiable(groups),
        _customResolver = resolver;

  /// Groups that control when this widget rebuilds.
  /// Default is {"*"} which means rebuild on all state changes.
  /// This set is unmodifiable to preserve widget immutability.
  final Set<String> groups;

  /// Optional scope keys for blocs.
  final Object? scope1;
  final Object? scope2;
  final Object? scope3;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// First bloc instance observed by this widget.
  @protected
  TBloc1 get bloc1 {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc1>();
    }
    return BlocScope.peekExisting<TBloc1>(scope: scope1);
  }

  /// Second bloc instance observed by this widget.
  @protected
  TBloc2 get bloc2 {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc2>();
    }
    return BlocScope.peekExisting<TBloc2>(scope: scope2);
  }

  /// Third bloc instance observed by this widget.
  @protected
  TBloc3 get bloc3 {
    if (_customResolver != null) {
      return _customResolver.resolve<TBloc3>();
    }
    return BlocScope.peekExisting<TBloc3>(scope: scope3);
  }

  @override
  @protected
  @mustCallSuper
  Widget build(BuildContext context) {
    if (_customResolver != null) {
      // Legacy path: resolve once and pass to builder
      final b1 = _customResolver.resolve<TBloc1>();
      final b2 = _customResolver.resolve<TBloc2>();
      final b3 = _customResolver.resolve<TBloc3>();
      return _buildAsyncBuilder(b1, b2, b3);
    }

    // New path: use BlocScope with lease holders
    return _BlocLeaseHolder3<TBloc1, TBloc2, TBloc3>(
      scope1: scope1,
      scope2: scope2,
      scope3: scope3,
      builder: (b1, b2, b3) => _buildAsyncBuilder(b1, b2, b3),
    );
  }

  Widget _buildAsyncBuilder(TBloc1 b1, TBloc2 b2, TBloc3 b3) {
    return JuiceAsyncBuilder<StreamStatus>(
      initial: b1.currentStatus,
      initiator: onInit,
      stream: MergeStream<StreamStatus>([b1.stream, b2.stream, b3.stream])
          .where((status) {
        if (denyRebuild(event: status.event, key: key, rebuildGroups: groups)) {
          return false;
        }
        return onStateChange(status);
      }),
      waiting: (context, status) => _build(context, status),
      builder: (context, status) => _build(context, status),
      error: (c, status, o, s) => _build(c, status),
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

// ============================================================================
// Internal Lease Holder Widgets
// ============================================================================

/// Internal widget that manages bloc lease lifecycle for a single bloc.
///
/// Acquires a lease in initState and releases it in dispose.
/// This ensures proper lifecycle management for leased blocs.
class _BlocLeaseHolder<TBloc extends JuiceBloc<BlocState>>
    extends StatefulWidget {
  const _BlocLeaseHolder({
    required this.builder,
    this.scope,
    super.key,
  });

  final Object? scope;
  final Widget Function(TBloc bloc) builder;

  @override
  State<_BlocLeaseHolder<TBloc>> createState() =>
      _BlocLeaseHolderState<TBloc>();
}

class _BlocLeaseHolderState<TBloc extends JuiceBloc<BlocState>>
    extends State<_BlocLeaseHolder<TBloc>> {
  late final BlocLease<TBloc> _lease;

  @override
  void initState() {
    super.initState();
    _lease = BlocScope.lease<TBloc>(scope: widget.scope);
  }

  @override
  void dispose() {
    _lease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_lease.bloc);
  }
}

/// Internal widget that manages bloc lease lifecycle for two blocs.
class _BlocLeaseHolder2<TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>> extends StatefulWidget {
  const _BlocLeaseHolder2({
    required this.builder,
    this.scope1,
    this.scope2,
    super.key,
  });

  final Object? scope1;
  final Object? scope2;
  final Widget Function(TBloc1 bloc1, TBloc2 bloc2) builder;

  @override
  State<_BlocLeaseHolder2<TBloc1, TBloc2>> createState() =>
      _BlocLeaseHolder2State<TBloc1, TBloc2>();
}

class _BlocLeaseHolder2State<TBloc1 extends JuiceBloc<BlocState>,
        TBloc2 extends JuiceBloc<BlocState>>
    extends State<_BlocLeaseHolder2<TBloc1, TBloc2>> {
  late final BlocLease<TBloc1> _lease1;
  late final BlocLease<TBloc2> _lease2;

  @override
  void initState() {
    super.initState();
    _lease1 = BlocScope.lease<TBloc1>(scope: widget.scope1);
    _lease2 = BlocScope.lease<TBloc2>(scope: widget.scope2);
  }

  @override
  void dispose() {
    _lease1.dispose();
    _lease2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_lease1.bloc, _lease2.bloc);
  }
}

/// Internal widget that manages bloc lease lifecycle for three blocs.
class _BlocLeaseHolder3<
    TBloc1 extends JuiceBloc<BlocState>,
    TBloc2 extends JuiceBloc<BlocState>,
    TBloc3 extends JuiceBloc<BlocState>> extends StatefulWidget {
  const _BlocLeaseHolder3({
    required this.builder,
    this.scope1,
    this.scope2,
    this.scope3,
    super.key,
  });

  final Object? scope1;
  final Object? scope2;
  final Object? scope3;
  final Widget Function(TBloc1 bloc1, TBloc2 bloc2, TBloc3 bloc3) builder;

  @override
  State<_BlocLeaseHolder3<TBloc1, TBloc2, TBloc3>> createState() =>
      _BlocLeaseHolder3State<TBloc1, TBloc2, TBloc3>();
}

class _BlocLeaseHolder3State<
        TBloc1 extends JuiceBloc<BlocState>,
        TBloc2 extends JuiceBloc<BlocState>,
        TBloc3 extends JuiceBloc<BlocState>>
    extends State<_BlocLeaseHolder3<TBloc1, TBloc2, TBloc3>> {
  late final BlocLease<TBloc1> _lease1;
  late final BlocLease<TBloc2> _lease2;
  late final BlocLease<TBloc3> _lease3;

  @override
  void initState() {
    super.initState();
    _lease1 = BlocScope.lease<TBloc1>(scope: widget.scope1);
    _lease2 = BlocScope.lease<TBloc2>(scope: widget.scope2);
    _lease3 = BlocScope.lease<TBloc3>(scope: widget.scope3);
  }

  @override
  void dispose() {
    _lease1.dispose();
    _lease2.dispose();
    _lease3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_lease1.bloc, _lease2.bloc, _lease3.bloc);
  }
}
