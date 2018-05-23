import 'package:app/config/app.dart';
import 'package:magic/magic.dart';

main() {
  new Magic().boot(config: appConfig, environment: {
    'app.env': 'development',
    'api.url': 'http://localhost:8000/api/'
  });
}