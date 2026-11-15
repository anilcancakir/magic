import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:material_ui/material_ui.dart';

/// Controller the form binds to; [ValidatesRequests] is what [MagicForm] reads.
class _FormController extends MagicController with ValidatesRequests {}

/// Pushes a route holding a [MagicForm] with [onWillPop] above a home route,
/// so a back attempt has somewhere to go.
Future<NavigatorState> _pumpFormRoute(
  WidgetTester tester, {
  required Future<bool> Function() onWillPop,
}) async {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final _FormController controller = _FormController();
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
  );

  navigatorKey.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => MagicForm(
        formKey: GlobalKey<FormState>(),
        controller: controller,
        onWillPop: onWillPop,
        child: const Text('form'),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return navigatorKey.currentState!;
}

void main() {
  group('MagicForm.onWillPop', () {
    testWidgets('a false answer keeps the form route on screen', (
      tester,
    ) async {
      var asked = 0;
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () async {
          asked++;
          return false;
        },
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('a true answer pops the form route', (tester) async {
      var asked = 0;
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () async {
          asked++;
          return true;
        },
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(find.text('form'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('an approval that lands after a push does not pop the new '
        'route', (tester) async {
      final Completer<bool> answer = Completer<bool>();
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () => answer.future,
      );

      // 1. Ask, and push another route while the answer is pending.
      unawaited(navigator.maybePop());
      await tester.pump();
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('other')),
      );
      await tester.pumpAndSettle();

      // 2. The approval belongs to the form route, which is no longer on top.
      answer.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('other'), findsOneWidget);
    });

    testWidgets('an approved back on the first route bubbles instead of '
        'removing it', (tester) async {
      final List<String> platformCalls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          platformCalls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MagicForm(
            formKey: GlobalKey<FormState>(),
            controller: controller,
            onWillPop: () async => true,
            child: const Text('form'),
          ),
        ),
      );

      // The system back button, as the engine sends it.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('form'), findsOneWidget);
      expect(platformCalls, contains('SystemNavigator.pop'));
    });

    testWidgets('an approved back on the only page of a layout bubbles out of '
        'the app', (tester) async {
      final List<String> platformCalls = _recordPlatformCalls(tester);
      MagicApp.reset();
      Magic.flush();
      TitleManager.reset();
      MagicRouter.reset();
      addTearDown(MagicRouter.reset);
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);

      // The shell page is first on the root navigator and the form page is
      // the only page in the shell's navigator.
      MagicRoute.group(
        layout: (Widget child) => child,
        routes: () {
          MagicRoute.page(
            '/',
            () => MagicForm(
              formKey: GlobalKey<FormState>(),
              controller: controller,
              onWillPop: () async => true,
              child: const Text('form'),
            ),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: MagicRouter.instance.routerConfig),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('form'), findsOneWidget);
      expect(platformCalls, contains('SystemNavigator.pop'));
    });
  });
}

/// Records the platform channel calls, where `SystemNavigator.pop` lands.
List<String> _recordPlatformCalls(WidgetTester tester) {
  final List<String> calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      calls.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  return calls;
}
