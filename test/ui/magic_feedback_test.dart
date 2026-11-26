import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Covers the overlay-delivered toast path: it must render in a Scaffold-less
/// (Wind-only) view, replace a previous toast, and auto-dismiss without the
/// late timer throwing on an already-detached entry.
void main() {
  setUp(() => Magic.flush());
  tearDown(() => Magic.flush());

  // WindTheme sits ABOVE MaterialApp so the Navigator overlay (where the toast
  // is inserted) can resolve it; the home is Scaffold-less on purpose.
  Widget harness({Brightness brightness = Brightness.light}) {
    return WindTheme(
      data: WindThemeData(brightness: brightness, syncWithSystem: false),
      child: MaterialApp(
        navigatorKey: MagicRouter.instance.navigatorKey,
        home: const SizedBox.shrink(),
      ),
    );
  }

  testWidgets('shows in a Scaffold-less view and auto-dismisses cleanly', (
    tester,
  ) async {
    await tester.pumpWidget(harness());

    MagicFeedback.info('Heads up', 'It works without a Scaffold');
    await tester.pump();

    expect(find.text('Heads up'), findsOneWidget);
    expect(find.text('It works without a Scaffold'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Auto-dismiss after the duration; the late timer must not throw on the
    // (now removed) entry.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Heads up'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second toast replaces the first', (tester) async {
    await tester.pumpWidget(harness());

    MagicFeedback.success('First', '');
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    MagicFeedback.error('Second', '');
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('degrades without throwing when no context and the log service is '
      'unbound', () {
    // No harness pumped (so no navigator context) and `log` is unbound (setUp
    // only flushes). The degrade path must fall back to debugPrint, not throw
    // "Service [log] is not registered" into the caller.
    expect(
      () => MagicFeedback.error('No context', 'should not throw'),
      returnsNormally,
    );
  });

  group('closeDialog result', () {
    testWidgets('Magic.dialog completes with the value passed to closeDialog', (
      tester,
    ) async {
      await tester.pumpWidget(harness());

      final Future<String?> answer = Magic.dialog<String>(const Text('Pick'));
      await tester.pumpAndSettle();
      expect(find.text('Pick'), findsOneWidget);

      Magic.closeDialog('x');
      await tester.pumpAndSettle();

      expect(await answer, 'x');
      expect(find.text('Pick'), findsNothing);
    });

    testWidgets('closeDialog without a result completes with null', (
      tester,
    ) async {
      await tester.pumpWidget(harness());

      final Future<String?> answer = Magic.dialog<String>(const Text('Pick'));
      await tester.pumpAndSettle();

      Magic.closeDialog();
      await tester.pumpAndSettle();

      expect(await answer, isNull);
    });
  });

  group('confirm label colour', () {
    testWidgets('defaults to text-white', (tester) async {
      await tester.pumpWidget(harness());

      unawaited(MagicFeedback.confirm(title: 'Delete?', message: 'Sure?'));
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Confirm'), const Color(0xffffffff));
    });

    testWidgets('reads view.confirm.button_confirm_text_class', (tester) async {
      Config.set('view.confirm.button_confirm_text_class', 'text-gray-900');
      await tester.pumpWidget(harness());

      unawaited(MagicFeedback.confirm(title: 'Delete?', message: 'Sure?'));
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Confirm'), gray(900));
    });

    testWidgets('reads view.confirm.button_danger_text_class when dangerous', (
      tester,
    ) async {
      Config.set('view.confirm.button_confirm_text_class', 'text-gray-900');
      Config.set('view.confirm.button_danger_text_class', 'text-gray-100');
      await tester.pumpWidget(harness());

      unawaited(
        MagicFeedback.confirm(
          title: 'Delete?',
          message: 'Sure?',
          isDangerous: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Confirm'), gray(100));
    });
  });

  group('snackbar position', () {
    testWidgets('defaults to the bottom of the screen', (tester) async {
      await tester.pumpWidget(harness());

      MagicFeedback.info('Heads up', '');
      await tester.pump();

      final Positioned positioned = toastPosition(tester, 'Heads up');
      expect(positioned.bottom, 0);
      expect(positioned.top, isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('view.snackbar.position top pins it to the top', (
      tester,
    ) async {
      Config.set('view.snackbar.position', 'top');
      await tester.pumpWidget(harness());

      MagicFeedback.info('Heads up', '');
      await tester.pump();

      final Positioned positioned = toastPosition(tester, 'Heads up');
      expect(positioned.top, 0);
      expect(positioned.bottom, isNull);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('a toast stays at the bottom when snackbars move to the top', (
      tester,
    ) async {
      Config.set('view.snackbar.position', 'top');
      await tester.pumpWidget(harness());

      MagicFeedback.toast('Copied');
      await tester.pump();

      expect(toastPosition(tester, 'Copied').bottom, 0);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });

  group('dialog barrier', () {
    testWidgets('defaults to a dismissible black/50 barrier', (tester) async {
      await tester.pumpWidget(harness());

      final Future<String?> answer = Magic.dialog<String>(const Text('Pick'));
      await tester.pumpAndSettle();

      expect(barrierColor(tester), blackAt(0.5));

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Pick'), findsNothing);
      expect(await answer, isNull);
    });

    testWidgets('reads view.dialog.barrier_color and barrier_dismissible', (
      tester,
    ) async {
      Config.set('view.dialog.barrier_color', 'bg-black/80');
      Config.set('view.dialog.barrier_dismissible', false);
      await tester.pumpWidget(harness());

      unawaited(Magic.dialog<String>(const Text('Pick')));
      await tester.pumpAndSettle();

      expect(barrierColor(tester), blackAt(0.8));

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Pick'), findsOneWidget);

      Magic.closeDialog();
      await tester.pumpAndSettle();
    });

    testWidgets('an explicit barrierDismissible wins over the config', (
      tester,
    ) async {
      Config.set('view.dialog.barrier_dismissible', true);
      await tester.pumpWidget(harness());

      unawaited(
        Magic.dialog<String>(const Text('Pick'), barrierDismissible: false),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Pick'), findsOneWidget);

      Magic.closeDialog();
      await tester.pumpAndSettle();
    });

    testWidgets('confirm reads the dialog barrier keys', (tester) async {
      Config.set('view.dialog.barrier_color', 'bg-black/80');
      Config.set('view.dialog.barrier_dismissible', false);
      await tester.pumpWidget(harness());

      unawaited(MagicFeedback.confirm(title: 'Delete?', message: 'Sure?'));
      await tester.pumpAndSettle();

      expect(barrierColor(tester), blackAt(0.8));

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('loading reads view.loading.barrier_class', (tester) async {
      Config.set('view.loading.barrier_class', 'bg-black/80');
      await tester.pumpWidget(harness());

      MagicFeedback.showLoading();
      // The loading dialog's spinner never settles: pump the open transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(barrierColor(tester), blackAt(0.8));

      MagicFeedback.closeLoading();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('the default barrier darkens under a dark WindTheme', (
      tester,
    ) async {
      Config.merge(defaultViewConfig);
      await tester.pumpWidget(harness(brightness: Brightness.dark));

      unawaited(Magic.dialog<String>(const Text('Pick')));
      await tester.pumpAndSettle();

      expect(barrierColor(tester), blackAt(0.7));

      Magic.closeDialog();
      await tester.pumpAndSettle();
    });
  });

  group('default styles in dark mode', () {
    testWidgets('the confirm container and title resolve dark colours', (
      tester,
    ) async {
      Config.merge(defaultViewConfig);
      await tester.pumpWidget(harness(brightness: Brightness.dark));

      unawaited(MagicFeedback.confirm(title: 'Sign out?', message: 'Sure?'));
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Sign out?'), gray(100));
      expect(textColor(tester, 'Sure?'), gray(400));
      expect(backgroundColor(tester, 'Sign out?'), gray(900));
    });

    testWidgets('the confirm container and title stay light in light mode', (
      tester,
    ) async {
      Config.merge(defaultViewConfig);
      await tester.pumpWidget(harness());

      unawaited(MagicFeedback.confirm(title: 'Sign out?', message: 'Sure?'));
      await tester.pumpAndSettle();

      expect(textColor(tester, 'Sign out?'), gray(900));
      expect(backgroundColor(tester, 'Sign out?'), const Color(0xffffffff));
    });
  });
}

/// The resolved text colour of the [RenderParagraph] showing [text].
Color? textColor(WidgetTester tester, String text) {
  final RenderParagraph paragraph = tester.renderObject(find.text(text));

  return paragraph.text.style?.color;
}

/// The nearest background colour painted behind [text].
Color? backgroundColor(WidgetTester tester, String text) {
  final Iterable<DecoratedBox> boxes = tester.widgetList<DecoratedBox>(
    find.ancestor(of: find.text(text), matching: find.byType(DecoratedBox)),
  );

  for (final DecoratedBox box in boxes) {
    final Decoration decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.color != null) {
      return decoration.color;
    }
  }

  return null;
}

/// The colour of the topmost modal barrier.
Color? barrierColor(WidgetTester tester) {
  return tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).last.color;
}

/// The [Positioned] wrapping the overlay entry that shows [text].
Positioned toastPosition(WidgetTester tester, String text) {
  return tester.widget<Positioned>(
    find.ancestor(of: find.text(text), matching: find.byType(Positioned)).first,
  );
}

/// Matches black at [alpha], within the 8-bit quantisation of a parsed `/NN`.
Matcher blackAt(double alpha) {
  return isSameColorAs(
    const Color(0xff000000).withValues(alpha: alpha),
    threshold: 0.01,
  );
}

/// The default wind palette's gray at [shade].
Color gray(int shade) => (colors['gray'] as Map<int, Color>)[shade]!;
