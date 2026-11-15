import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:material_ui/material_ui.dart';

/// `MagicRoute.layout(routes: [...])` wraps its routes in the layout.
///
/// Its list is built with `MagicRoute.page`, which runs before `layout` sees
/// it and, with no group collecting, also lands each route in the top-level
/// table. go_router matches top-level routes before the shell, so a route
/// left in both places rendered bare, without the layout around it.
void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
    TitleManager.reset();
    MagicRouter.reset();
  });

  Widget shell(Widget child) => Column(
    children: [
      const Text('layout'),
      Expanded(child: child),
    ],
  );

  testWidgets('a standalone layout wraps the pages it was given', (
    tester,
  ) async {
    MagicRoute.page('/', () => const Text('home'));
    MagicRoute.layout(
      builder: shell,
      routes: [MagicRoute.page('/dashboard', () => const Text('dashboard'))],
    );
    await tester.pumpWidget(
      MaterialApp.router(routerConfig: MagicRouter.instance.routerConfig),
    );

    MagicRoute.to('/dashboard');
    await tester.pumpAndSettle();

    expect(find.text('dashboard'), findsOneWidget);
    expect(find.text('layout'), findsOneWidget);
  });

  test('its pages leave the top-level table and stay reachable by name', () {
    MagicRoute.layout(
      builder: shell,
      routes: [
        MagicRoute.page('/dashboard', () => const SizedBox()).name('dash'),
      ],
    );

    expect(MagicRouter.instance.routes, isEmpty);
    expect(MagicRouter.instance.allRoutes.map((route) => route.routeName), [
      'dash',
    ]);
  });
}
