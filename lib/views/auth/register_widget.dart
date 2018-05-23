import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

class RegisterWidget extends StatefulWidget {
  @override
  State<StatefulWidget> createState() {
    return new _RegisterWidgetState();
  }
}

class _RegisterWidgetState extends State<RegisterWidget> {
  final GlobalKey<FormState> _formKey = new GlobalKey<FormState>();
  Map<String, String> _data = {'name': '', 'email': '', 'password': '', 'password_confirmation': ''};

  void _submit(BuildContext context) async {
    if (_formKey.currentState.validate()) {
      _formKey.currentState.save();
      showLoader(context);

      try {
        bool success = await guard().register(this._data);
        hideLoader(context);

        if (success) {
          replaceTo(context, '/');
        } else {
          showError(context, trans(context, 'auth.register.failed'));
        }
      } on ApiException catch (e) {
        showError(context, e.getFirstError());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(
          trans(context, 'auth.register')
        ),
      ),
      body: new Form(
        key: this._formKey,
        child: new FormList(
          items: [
            new FormItem(
              input: new Input(
                name: 'name',
                type: InputType.string,
                onSaved: (String value) => this._data['name'] = value,
                validators: [
                  new RequiredValidator(),
                  new MinValidator(3),
                  new MaxValidator(127)
                ],
              ),
            ),
            new FormItem(
              input: new Input(
                name: 'email',
                type: InputType.email,
                onSaved: (String value) => this._data['email'] = value,
                validators: [
                  new RequiredValidator(),
                  new EmailValidator()
                ],
              ),
            ),
            new FormItem(
              input: new Input(
                name: 'password',
                type: InputType.password,
                onSaved: (String value) => this._data['password'] = value,
                validators: [
                  new RequiredValidator(),
                  new MinValidator(6)
                ],
              ),
            ),
            new FormItem(
              input: new Input(
                name: 'password_confirmation',
                type: InputType.password,
                onSaved: (String value) => this._data['password_confirmation'] = value,
                validators: [
                  new RequiredValidator(),
                  new MinValidator(6)
                ],
              ),
            ),
            new FormItem(
              input: new RaisedButton(
                child: new Text(trans(context, 'auth.register')),
                onPressed: () => this._submit(context),
              ),
            ),
            new FormItem(
              input: new FlatButton(
                child: new Text(trans(context, 'auth.login')),
                onPressed: () => Navigator.pop(context),
              ),
            )
          ],
        ),
      ),
    );
  }
}