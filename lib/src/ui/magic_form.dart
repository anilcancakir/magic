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
  /// swiped away: the form builds on Flutter's `PopScope` with
  /// `canPop: false`. An approval lifts that veto for one frame and asks
  /// `Navigator.maybePop` again, so the route's own pop logic runs: a web
  /// overlay that closes through the browser steps the browser back. As with
  /// `maybePop`, an answer that arrives after the route left the top of the
  /// stack is dropped, and an approved back on the first route bubbles
  /// through each enclosing navigator, then out of the app (on Android that
  /// closes it, including for a programmatic `maybePop`).
  ///
  /// Two differences from Flutter's deprecated `Form.onWillPop`, which come
  /// with `PopScope`: `Navigator.maybePop` answers `true` at once rather than
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
  /// Whether an approved back has lifted the pop veto for one frame.
  bool _approved = false;

  /// Whether [MagicForm.onWillPop] is being asked right now.
  bool _asking = false;

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

    final bool guarded = widget.onWillPop != null;

    return Form(
      key: effectiveFormKey,
      autovalidateMode: effectiveMode,
      onChanged: widget.onChanged,
      canPop: guarded ? _approved : null,
      onPopInvokedWithResult: guarded ? _onPopInvoked : null,
      child: widget.child,
    );
  }

  /// Asks [MagicForm.onWillPop] about a blocked back attempt and, on `true`,
  /// lifts the veto and asks `Navigator.maybePop` again, so the route
  /// finishes the pop with its own logic.
  Future<void> _onPopInvoked(bool didPop, Object? result) async {
    if (didPop || _approved || _asking) return;

    // 1. Bind the answer to the route that asked, before the await.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final List<NavigatorState> ancestors = <NavigatorState>[
      for (
        NavigatorState? nav = navigator.context
            .findAncestorStateOfType<NavigatorState>();
        nav != null;
        nav = nav.context.findAncestorStateOfType<NavigatorState>()
      )
        nav,
    ];

    // 2. Ask once; a throw is reported, never left to the caller's zone.
    final bool approved;
    _asking = true;
    try {
      approved = await widget.onWillPop!();
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
    } finally {
      _asking = false;
    }

    // 3. Like maybePop, forget the approval when the history changed while it
    //    was pending: the route left, or another one was pushed over it.
    if (!approved || !mounted || route == null || !route.isCurrent) return;

    // 4. Lift the veto for one frame, so PopScope reads canPop: true, and let
    //    the route decide: an overlay steps the browser back, a first route
    //    bubbles (maybePop answers false only then).
    setState(() => _approved = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (!route.isCurrent || await navigator.maybePop(result)) return;
      for (final NavigatorState ancestor in ancestors) {
        if (ancestor.mounted && await ancestor.maybePop(result)) return;
      }
      await SystemNavigator.pop();
    } finally {
      if (mounted) setState(() => _approved = false);
    }
  }
}
