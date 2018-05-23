import 'package:app/app/controllers/auth_controller.dart';
import 'package:fluro/fluro.dart';
import 'package:magic/magic.dart';

class AuthRoutes extends BaseRoutes {
  @override
  void register(Router router) {
    router.define('/auth/login', handler: new Handler(handlerFunc: (_, __) {
      return new AuthController().login();
    }));

    router.define('/auth/register', handler: new Handler(handlerFunc: (_, __) {
      return new AuthController().register();
    }));
  }
}