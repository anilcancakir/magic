import 'package:app/routes/auth_routes.dart';
import 'package:app/routes/global_routes.dart';

Map<String, dynamic> routeConfig = {
  /// Application routes
  'routes': [
    new GlobalRoutes(),
    new AuthRoutes()
  ]
};