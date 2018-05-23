import 'package:app/app/auth/api_guard.dart';

Map<String, dynamic> authConfig = {
  /// Default authentication guard
  'default': 'api',

  /// Authentication guards
  'guards': {
    'api': new ApiGuard()
  }
};