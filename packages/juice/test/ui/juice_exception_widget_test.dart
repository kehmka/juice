import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Pins for `JuiceExceptionWidget`: renders the exception and a trimmed stack
/// trace, copies both to the clipboard, and Dismiss pops the route.

void main() {
  final trace = StackTrace.fromString('   #0 frameA (a.dart:1)\n\t#1 frameB');

  Widget host(Widget child) => MaterialApp(home: child);

  testWidgets('renders title, exception text and trimmed stack trace',
      (tester) async {
    await tester.pumpWidget(host(JuiceExceptionWidget(
      exception: Exception('kaput'),
      stackTrace: trace,
    )));
    expect(find.text('Uncaught Exception'), findsOneWidget);
    expect(find.text('Error Details'), findsOneWidget);
    expect(find.text('Stack Trace'), findsOneWidget);
    expect(find.text('Exception: kaput'), findsOneWidget);
    expect(find.text('#0 frameA (a.dart:1)\n#1 frameB'), findsOneWidget,
        reason: 'each stack line is trimmed');
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('copy button writes exception + stack to clipboard',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(host(JuiceExceptionWidget(
      exception: const FormatException('fmt'),
      stackTrace: trace,
    )));
    await tester.tap(find.byIcon(Icons.copy));
    await tester.pump();

    expect(copied, startsWith('Exception:\nFormatException: fmt'));
    expect(copied, contains('\n\nStackTrace:\n'));
    expect(copied, contains('frameB'));
    expect(find.text('Error details copied to clipboard'), findsOneWidget);
  });

  testWidgets('Dismiss pops the current route', (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      home: const Text('home'),
    ));
    navKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => JuiceExceptionWidget(
        exception: Exception('pushed'),
        stackTrace: trace,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Uncaught Exception'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Uncaught Exception'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
