import 'package:app/config/auth.dart';
import 'package:magic/magic.dart';

class AuthServiceProvider extends BaseAuthServiceProvider {
  Map<String, dynamic> config = authConfig;
}