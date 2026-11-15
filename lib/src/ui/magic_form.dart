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
class MagicForm extends StatelessWidget {
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
  /// Asked on every back attempt (system back, `Navigator.maybePop`); the
  /// route pops only when the future answers `true`. While it is set the
  /// route cannot be swiped away, the same as Flutter's `PopScope` with
  /// `canPop: false`, which is what the form builds on. As with
  /// `Navigator.maybePop`, an answer that arrives after the route left the
  /// top of the stack is dropped, and an approved back on the first route
  /// bubbles to the enclosing navigator or out of the app.
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
  Widget build(BuildContext context) {
    // Extract formKey and controller from formData if provided
    final effectiveFormKey = formData?.formKey ?? formKey;
    final effectiveController = formData?.controller ?? controller;

    // Determine autovalidate mode
    AutovalidateMode effectiveMode =
        autovalidateMode ?? AutovalidateMode.disabled;

    // If controller has server-side errors relevant to THIS form,
    // force validation to show them. When formData is provided, only
    // errors matching this form's fields trigger autovalidation —
    // preventing cross-form error leakage in shared-controller setups.
    if (formData != null) {
      if (formData!.hasRelevantErrors) {
        effectiveMode = AutovalidateMode.always;
      }
    } else if (effectiveController is ValidatesRequests) {
      // Legacy path: no formData, fall back to global hasErrors check
      if (effectiveController.hasErrors) {
        effectiveMode = AutovalidateMode.always;
      }
    }

    final Future<bool> Function()? willPop = onWillPop;

    return Form(
      key: effectiveFormKey,
      autovalidateMode: effectiveMode,
      onChanged: onChanged,
      canPop: willPop == null ? null : false,
      onPopInvokedWithResult: willPop == null
          ? null
          : (bool didPop, Object? result) =>
                _popIfAllowed(context, willPop, didPop, result),
      child: child,
    );
  }

  /// Asks [willPop] about a blocked back attempt and, on `true`, finishes it
  /// the way `Navigator.maybePop` finishes an approved pop, so the veto keeps
  /// its `onWillPop` contract on top of `canPop: false`.
  Future<void> _popIfAllowed(
    BuildContext context,
    Future<bool> Function() willPop,
    bool didPop,
    Object? result,
  ) async {
    if (didPop) return;

    // 1. Bind the answer to the route that asked, before the await.
    final ModalRoute<Object?>? route = ModalRoute.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final NavigatorState? parent = navigator.context
        .findAncestorStateOfType<NavigatorState>();
    if (!await willPop()) return;

    // 2. Like maybePop, forget the approval when the history changed while it
    //    was pending: the route left, or another one was pushed over it.
    if (!context.mounted || route == null || !route.isCurrent) return;
    if (!route.isFirst) {
      navigator.pop(result);
      return;
    }

    // 3. A first route bubbles (RoutePopDisposition.bubble): to the enclosing
    //    navigator, or out of the app, instead of leaving a navigator empty.
    if (parent != null) {
      await parent.maybePop(result);
      return;
    }
    await SystemNavigator.pop();
  }
}
