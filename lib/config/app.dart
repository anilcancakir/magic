import 'package:app/app/providers/api_service_provider.dart';
import 'package:app/app/providers/auth_service_provider.dart';
import 'package:app/app/providers/data_service_provider.dart';
import 'package:app/app/providers/router_service_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

Map<String, dynamic> appConfig = {
  /// Application name
  'name': 'Magic',

  /// Application environment
  'env': 'production',

  /// Application locale
  'locale': new Locale('en', 'US'),

  /// Supported locales
  'supportedLocales': [
    new Locale('en', 'US')
  ],

  /// Application orientations
  'orientations': <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight
  ],

  /// Application service providers
  'providers': <ServiceProvider>[
    new RouterServiceProvider(),
    new AuthServiceProvider(),
    new ApiServiceProvider(),
    new DataServiceProvider()
  ]
};