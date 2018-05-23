import 'dart:async';
import 'dart:convert';

import 'package:app/app/models/user.dart';
import 'package:http/http.dart' as http;
import 'package:magic/magic.dart';

class ApiGuard extends Guard {
  /// The current active user.
  User _currentUser;

  /// The current bearer token.
  String _bearerToken;

  /// Attempt to login.
  @override
  Future<bool> attempt(Map<String, dynamic> credentials) async {
    final response = await apiClient().post('/auth/login', body: credentials);
    this._setUserFromResponse(response);

    return true;
  }

  /// Check the user logged-in.
  @override
  bool check() {
    return this._currentUser != null;
  }

  /// Get the bearer token.
  @override
  Future<String> getBearerToken() {
    return new Future.value(this._bearerToken);
  }

  /// Let's logout the user.
  @override
  void logout() {
    apiClient().post('/auth/logout');

    this._currentUser = null;
    this._bearerToken = null;

    cacheDelete(authUserCacheKey);
    cacheDelete(authBearerTokenCacheKey);
  }

  /// Try to register and login with the new user.
  @override
  Future<bool> register(Map<String, dynamic> credentials) async {
    final response = await apiClient().post('/auth/register', body: credentials);
    this._setUserFromResponse(response);

    return true;
  }

  /// Get the current user.
  @override
  User user() {
    return this._currentUser;
  }

  /// Set the current user from response.
  void _setUserFromResponse(http.Response response) {
    print(response.body);

    Map<String, dynamic> data = json.decode(response.body);

    this._currentUser = new User().make(data['data']);
    this._bearerToken = data['meta']['token'];

    cacheSet(authUserCacheKey, json.encode(data['data']));
    cacheSet(authBearerTokenCacheKey, this._bearerToken);
  }

  /// Set the current user.
  void setCurrentUser(dynamic data) {
    this._currentUser = new User().make(data);
  }

  /// Set the bearer token.
  void setBearerToken(String token) {
    this._bearerToken = token;
  }
}