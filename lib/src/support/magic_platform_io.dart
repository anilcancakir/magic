import 'dart:io';

/// Whether the running process is tvOS.
///
/// flutter-tvos reports `Platform.isIOS` and `TargetPlatform.iOS` for an Apple
/// TV, so the operating system name is the only thing that tells the two apart.
bool readIsTvOS() => Platform.operatingSystem == 'tvos';
