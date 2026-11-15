import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../concerns/validates_requests.dart';
import '../http/magic_controller.dart';
import 'magic_form_data.dart';

/// A Form widget that integrates with Magic's validation system.
///
/// `MagicForm` wraps Flutter's [Form] widget and automatically manages
/// `autovalidateMode` based on the controller's server-side validation errors.
///
/// ## Usage with MagicFormData (Recommended)
///
/// ```dart
/// class _RegisterViewState extends MagicStatefulViewState<AuthController, RegisterView> {
///   late final form = MagicFormData({
///     'email': '',
///     'password': '',
///     'accept_terms': false,
///   }, controller: controller);
///
///   @override
///   Widget build(BuildContext context) {
///     return MagicForm(
///       formData: form,  // Auto-extracts formKey and controller
///       child: Column(
///         children: [
///           form.field('email', rules: [Required(), Email()]),
///           form.checkbox('accept_terms'),
///           WButton(
///             onTap: () {
///               if (form.validate()) {
///                 controller.register(form.data);
///               }
///             },
///             child: Text('Submit'),
///           ),
///         ],
///       ),
///     );
///   }
/// }
/// ```
///
/// ## Usage with explicit formKey (Legacy)
///
/// ```dart
/// MagicForm(
///   formKey: _formKey,
///   controller: controller,
///   child: Column(...),
/// )
/// ```
class MagicForm extends StatefulWidget {
  /// The form data manager (recommended).
  ///
  /// When provided, `formKey` and `controller` are automatically extracted.
  final MagicFormData? formData;

  /// The form key for accessing form state.
  ///
  /// Optional when `formData` is provided.
  final GlobalKey<FormState>? formKey;

  /// The controller that may contain server-side validation errors.
  ///
  /// Optional when `formData` is provided.
  final MagicController? controller;

  /// The form content.
  final Widget child;

  /// Optional explicit autovalidate mode.
  ///
  /// If not provided, the form will automatically use:
  /// - `AutovalidateMode.always` when controller has errors
  /// - `AutovalidateMode.disabled` otherwise
  final AutovalidateMode? autovalidateMode;

  /// Called when one of the form fields changes.
  final VoidCallback? onChanged;

  /// Enables the form to veto attempts by the user to dismiss the
  /// [ModalRoute] that contains the form.
  ///
  /// Asked on a back attempt (system back, `Navigator.maybePop`); the route
  /// pops only when the future answers `true`, and a second attempt while
  /// one is pending is not asked again. While it is set the route cannot be
  /// swiped away: the route holds one pop veto (a `PopEntry`) for every
  /// guarded `MagicForm` on it. A back attempt asks each form's callback in
  /// turn, in the order the forms mounted, and stops at the first refusal.
  /// When all approve, the veto is lifted only while `Navigator.maybePop`
  /// runs again (microtasks, no frame, unless the route also carries a
  /// legacy async `willPop` callback), so the route's own pop logic decides: a
  /// web overlay that closes through the browser steps the browser back. As
  /// with `maybePop`, an answer that arrives after the route, or the page
  /// holding its navigator, left the top of the stack is dropped, and an
  /// approved back on the first route bubbles through each enclosing
  /// navigator, then out of the app (on Android that closes it, including
  /// for a programmatic `maybePop`).
  ///
  /// Two differences from Flutter's deprecated `Form.onWillPop`, which come
  /// with the move to pop entries: `Navigator.maybePop` answers `true` at once rather than
  /// after the callback, and an exception the callback throws is reported
  /// through `FlutterError.reportError` instead of from the `maybePop` call.
  /// `Navigator.pop` is never vetoed, as before.
  final Future<bool> Function()? onWillPop;

  /// Restoration ID to save and restore the state of the [Form].
  final String? restorationId;

  /// Creates a MagicForm.
  ///
  /// Either `formData` or both `formKey` and `controller` must be provided.
  const MagicForm({
    super.key,
    this.formData,
    this.formKey,
    this.controller,
    required this.child,
    this.autovalidateMode,
    this.onChanged,
    this.onWillPop,
    this.restorationId,
  }) : assert(
         formData != null || controller != null,
         'Either formData or controller must be provided',
       );

  @override
  State<MagicForm> createState() => _MagicFormState();
}

class _MagicFormState extends State<MagicForm> {
  /// The guard of the route this form vetoes on, while it has a callback.
  _RouteGuard? _guard;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach();
  }

  @override
  void didUpdateWidget(MagicForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach();
  }

  @override
  void dispose() {
    _guard?.remove(this);
    super.dispose();
  }

  /// Joins the guard of the enclosing route while [MagicForm.onWillPop] is
  /// set, and leaves it otherwise.
  void _attach() {
    final ModalRoute<Object?>? route = widget.onWillPop == null
        ? null
        : ModalRoute.of(context);
    if (_guard?.route == route) return;
    _guard?.remove(this);
    _guard = route == null ? null : (_RouteGuard.of(route)..add(this));
  }

  @override
  Widget build(BuildContext context) {
    final MagicFormData? formData = widget.formData;

    // Extract formKey and controller from formData if provided
    final effectiveFormKey = formData?.formKey ?? widget.formKey;
    final effectiveController = formData?.controller ?? widget.controller;

    // Determine autovalidate mode
    AutovalidateMode effectiveMode =
        widget.autovalidateMode ?? AutovalidateMode.disabled;

    // If controller has server-side errors relevant to THIS form,
    // force validation to show them. When formData is provided, only
    // errors matching this form's fields trigger autovalidation —
    // preventing cross-form error leakage in shared-controller setups.
    if (formData != null) {
      if (formData.hasRelevantErrors) {
        effectiveMode = AutovalidateMode.always;
      }
    } else if (effectiveController is ValidatesRequests) {
      // Legacy path: no formData, fall back to global hasErrors check
      if (effectiveController.hasErrors) {
        effectiveMode = AutovalidateMode.always;
      }
    }

    return Form(
      key: effectiveFormKey,
      autovalidateMode: effectiveMode,
      onChanged: widget.onChanged,
      child: widget.child,
    );
  }
}

/// The one pop veto a route holds for every guarded [MagicForm] on it.
///
/// A `PopEntry` of its own rather than each form's `PopScope`: the forms are
/// asked in turn by one leader and the route pops once when all approve, and
/// the veto is lifted synchronously, only while that `maybePop` runs.
class _RouteGuard extends PopEntry<Object?> {
  _RouteGuard._(this.route);

  static final Expando<_RouteGuard> _guards = Expando<_RouteGuard>();

  /// The guard of [route], created and registered on first use.
  static _RouteGuard of(ModalRoute<Object?> route) =>
      _guards[route] ??= _RouteGuard._(route);

  final ModalRoute<Object?> route;
  final List<_MagicFormState> _forms = <_MagicFormState>[];
  final ValueNotifier<bool> _canPop = ValueNotifier<bool>(false);
  bool _running = false;

  @override
  ValueListenable<bool> get canPopNotifier => _canPop;

  void add(_MagicFormState form) {
    if (_forms.isEmpty) route.registerPopEntry(this);
    _forms.add(form);
  }

  void remove(_MagicFormState form) {
    _forms.remove(form);
    if (_forms.isNotEmpty) return;
    route.unregisterPopEntry(this);
    _guards[route] = null;
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop || _running || _forms.isEmpty) return;
    _running = true;
    _ask(result).whenComplete(() => _running = false);
  }

  /// Asks every form in turn and, when all approve, lets the route finish
  /// the pop with its own logic.
  Future<void> _ask(Object? result) async {
    // 1. Bind the attempt to its navigator chain before any await.
    final BuildContext context = _forms.first.context;
    final List<NavigatorState> chain = <NavigatorState>[
      for (
        NavigatorState? nav = Navigator.of(context);
        nav != null;
        nav = nav.context.findAncestorStateOfType<NavigatorState>()
      )
        nav,
    ];
    final List<ModalRoute<Object?>?> holders = <ModalRoute<Object?>?>[
      for (final NavigatorState nav in chain.take(chain.length - 1))
        ModalRoute.of(nav.context),
    ];

    // 2. One answer per form; a refusal or a throw ends the attempt.
    for (final _MagicFormState form in List<_MagicFormState>.of(_forms)) {
      final Future<bool> Function()? willPop = form.widget.onWillPop;
      if (!form.mounted || willPop == null) continue;
      try {
        if (!await willPop()) return;
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'magic',
            context: ErrorDescription('while asking MagicForm.onWillPop'),
          ),
        );
        return;
      }
    }

    // 3. Like maybePop, drop a late approval: the route must still be on
    //    top, and so must the page holding each enclosing navigator (as
    //    go_router's walk over the current navigators reads it).
    if (!route.isCurrent) return;
    if (holders.any(
      (ModalRoute<Object?>? page) => !(page?.isCurrent ?? true),
    )) {
      return;
    }

    // 4. Lift the veto while the route decides (an overlay steps the browser
    //    back); a first route bubbles, the only case maybePop answers false.
    _canPop.value = true;
    try {
      for (final NavigatorState nav in chain) {
        if (nav.mounted && await nav.maybePop(result)) return;
      }
      await SystemNavigator.pop();
    } finally {
      _canPop.value = false;
    }
  }
}
