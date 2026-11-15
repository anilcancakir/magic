import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic/src/routing/magic_overlay_page.dart';
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

    testWidgets('an approved close of an overlay that closes through the '
        'browser steps the browser back', (tester) async {
      var stepped = 0;
      var removed = 0;
      final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            key: key,
            pages: <Page<Object?>>[
              const MaterialPage<void>(child: Text('base')),
              MagicOverlayPage<void>(
                closesThroughBrowser: () => true,
                stepBrowserBack: ([VoidCallback? onGivenUp]) => stepped++,
                child: MagicForm(
                  formKey: GlobalKey<FormState>(),
                  controller: controller,
                  onWillPop: () async => true,
                  child: const Text('form'),
                ),
              ),
            ],
            onDidRemovePage: (_) => removed++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await key.currentState!.maybePop();
      await tester.pumpAndSettle();

      // The overlay's own pop logic runs: the browser steps back and the
      // router, not the navigator, removes the page.
      expect(stepped, 1);
      expect(removed, 0);
    });

    testWidgets('a callback that throws keeps the route', (tester) async {
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () async => throw StateError('no answer'),
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('a callback that never answers keeps the route, and a second '
        'back does not ask again', (tester) async {
      var asked = 0;
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () {
          asked++;
          return Completer<bool>().future;
        },
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();
      await navigator.maybePop();
      await tester.pumpAndSettle();

      expect(asked, 1);
      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('an answer that lands after the form left is dropped', (
      tester,
    ) async {
      final List<String> platformCalls = _recordPlatformCalls(tester);
      final Completer<bool> answer = Completer<bool>();
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () => answer.future,
      );

      unawaited(navigator.maybePop());
      await tester.pump();
      navigator.pop(); // the form route goes while the answer is pending
      await tester.pumpAndSettle();

      answer.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('two forms that both approve, at different times, pop the '
        'route once and are each asked once', (tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);
      var askedA = 0;
      var askedB = 0;
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Column(
            children: [
              MagicForm(
                formKey: GlobalKey<FormState>(),
                controller: controller,
                onWillPop: () async {
                  askedA++;
                  return true;
                },
                child: const Text('form'),
              ),
              MagicForm(
                formKey: GlobalKey<FormState>(),
                controller: controller,
                onWillPop: () async {
                  askedB++;
                  // A dialog's answer: later than the first form's.
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                  return true;
                },
                child: const Text('other form'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await navigatorKey.currentState!.maybePop();
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
      expect(askedA, 1);
      expect(askedB, 1);
    });

    testWidgets('a late approval on a layout page does not pop a page pushed '
        'over the shell meanwhile', (tester) async {
      final List<String> platformCalls = _recordPlatformCalls(tester);
      MagicApp.reset();
      Magic.flush();
      TitleManager.reset();
      MagicRouter.reset();
      addTearDown(MagicRouter.reset);
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);
      final Completer<bool> answer = Completer<bool>();

      MagicRoute.group(
        layout: (Widget child) => child,
        routes: () {
          MagicRoute.page(
            '/',
            () => MagicForm(
              formKey: GlobalKey<FormState>(),
              controller: controller,
              onWillPop: () => answer.future,
              child: const Text('form'),
            ),
          );
        },
      );
      MagicRoute.page('/other', () => const Text('other'));
      await tester.pumpWidget(
        MaterialApp.router(routerConfig: MagicRouter.instance.routerConfig),
      );
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pump();
      MagicRoute.push('/other'); // lands on the root navigator, over the shell
      await tester.pumpAndSettle();

      answer.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('other'), findsOneWidget);
      expect(platformCalls, isNot(contains('SystemNavigator.pop')));
    });

    testWidgets('one form on a route vetoes even when another approves', (
      tester,
    ) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final _FormController controller = _FormController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigatorKey, home: const Text('home')),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Column(
            children: [
              MagicForm(
                formKey: GlobalKey<FormState>(),
                controller: controller,
                onWillPop: () async => true,
                child: const Text('form'),
              ),
              MagicForm(
                formKey: GlobalKey<FormState>(),
                controller: controller,
                onWillPop: () async => false,
                child: const Text('other form'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await navigatorKey.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('form'), findsOneWidget);
    });

    testWidgets('Navigator.pop is not vetoed', (tester) async {
      var asked = 0;
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () async {
          asked++;
          return false;
        },
      );

      navigator.pop();
      await tester.pumpAndSettle();

      expect(asked, 0);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a refused back can be approved on the next attempt', (
      tester,
    ) async {
      var answer = false;
      final navigator = await _pumpFormRoute(
        tester,
        onWillPop: () async => answer,
      );

      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('form'), findsOneWidget);

      answer = true;
      await navigator.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
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
