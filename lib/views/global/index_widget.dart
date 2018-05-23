import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

class IndexWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(title: new Text(
        config('app.name')
      )),
      body: new ListView(
        children: <Widget>[
          new ListTile(
            title: new RaisedButton(
              child: new Text(trans(context, 'auth.logout')),
              onPressed: () => this._clickLogout(context),
            ),
          )
        ],
      ),
    );
  }

  void _clickLogout(BuildContext context) {
    guard().logout();
    replaceTo(context, '/auth/login');
  }
}