import 'package:app/app/controllers/auth_controller.dart';
import 'package:app/app/controllers/global_controller.dart';
import 'package:fluro/fluro.dart';
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

class GlobalRoutes extends BaseRoutes {
  @override
  void register(Router router) {
    router.define('/', handler: new Handler(handlerFunc: (BuildContext context, __) {
      if (auth().check()) {
        return new GlobalController().index();
      }

      return new AuthController().login();
    }));
  }
}