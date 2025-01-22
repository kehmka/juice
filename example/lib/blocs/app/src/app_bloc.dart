import 'package:juice/juice.dart';

import '../app.dart';

class AppBloc extends JuiceBloc<AppState> {
  final navigatorKey = GlobalKey<NavigatorState>();
  AppBloc({required DeepLinkConfig deeplinkconfig})
      : super(
          AppState(),
          [], // No specific use cases needed for deep linking demo
          [
            () => DeepLinkAviator(
                  name: 'deepLink',
                  navigate: (args) {
                    final bloc =
                        GlobalBlocResolver().resolver.resolve<AppBloc>();
                    final route = args['route'] as String;
                    JuiceLoggerConfig.logger.log("Navigating to route: $route");
                    bloc.navigatorKey.currentState?.pushNamed(route);
                  },
                  config: deeplinkconfig,
                ),
          ],
        );
}
