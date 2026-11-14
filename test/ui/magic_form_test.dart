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
  });
}
