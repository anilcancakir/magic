import 'package:magic/magic.dart';

class User extends Model implements Authenticatable {
  @override
  getAuthIdentifier() {
    return this.primaryKey();
  }

  @override
  String primaryKey() {
    return 'id';
  }

  @override
  String resourceKey() {
    return 'users';
  }
}