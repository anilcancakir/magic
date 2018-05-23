import 'package:app/views/auth/login_widget.dart';
import 'package:app/views/auth/register_widget.dart';
import 'package:flutter/material.dart';

class AuthController {
  Widget login() {
    return new LoginWidget();
  }

  Widget register() {
    return new RegisterWidget();
  }
}