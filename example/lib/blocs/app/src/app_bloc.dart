import 'package:juice/juice.dart';

import '../app.dart';

class AppBloc extends JuiceBloc<AppState> {
  final GlobalKey<NavigatorState> navigatorKey;

  AppBloc({required DeepLinkConfig deeplinkconfig})
      : this._(deeplinkconfig, GlobalKey<NavigatorState>());

  // The key arrives as an initializing formal so the aviator closure below
  // captures the PARAMETER — reading the instance field from a super
  // initializer is a compile error on current Dart.
  AppBloc._(DeepLinkConfig deeplinkconfig, this.navigatorKey)
      : super(
          AppState(),
          [], // No specific use cases needed for deep linking demo
          [
            () => DeepLinkAviator(
                  name: 'deepLink',
                  navigate: (args) {
                    final route = args['route'] as String;
                    JuiceLoggerConfig.logger.log('Navigating to route: $route');
                    navigatorKey.currentState?.pushNamed(route);
                  },
                  config: deeplinkconfig,
                ),
          ],
        );
}
