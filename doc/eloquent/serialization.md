# Eloquent: Serialization

Eloquent models can be serialized to maps and JSON strings with a single call, with support for hiding sensitive attributes and appending computed values to every serialized output.

- [Introduction](#introduction)
- [Serializing to Arrays](#serializing-to-arrays)
- [Serializing to JSON](#serializing-to-json)
- [Hiding Attributes](#hiding-attributes)
- [Appending Attributes](#appending-attributes)
- [API Response Example](#api-response-example)
- [Related Documentation](#related-documentation)

<a name="introduction"></a>
## Introduction

When building APIs or passing data to JavaScript frontends, you will often need to convert your models to arrays or JSON. Magic includes convenient methods for these conversions while controlling which attributes are included.

<a name="serializing-to-arrays"></a>
## Serializing to Arrays

Convert a model to an array using `toMap()`:

```dart
final user = await User.find(1);
final array = user?.toMap();

// {
//   'id': 1,
//   'name': 'John Doe',
//   'email': 'john@example.com',
//   'created_at': '2024-01-15T10:30:00.000Z',
//   'updated_at': '2024-01-15T10:30:00.000Z',
// }
```

### Converting Collections

```dart
final users = await User.all();
final array = users.map((u) => u.toMap()).toList();
```

<a name="serializing-to-json"></a>
## Serializing to JSON

Convert a model to JSON using `toJson()`:

```dart
final user = await User.find(1);
final json = user?.toJson();

// '{"id":1,"name":"John Doe","email":"john@example.com",...}'
```

<a name="hiding-attributes"></a>
## Hiding Attributes

### Model-Level Hidden Attributes

Define attributes that should never be serialized:

```dart
class User extends Model {
  @override
  List<String> get hidden => ['password', 'remember_token', 'api_key'];
}
```

Now when you call `toMap()` or `toJson()`, these attributes are excluded:

```dart
final user = await User.find(1);
print(user?.toMap());

// {
//   'id': 1,
//   'name': 'John Doe',
//   'email': 'john@example.com',
//   // password, remember_token, api_key are NOT included
// }
```

### Runtime Hidden Attributes

Hide additional attributes on one model instance:

```dart
final user = await User.find(1);
final array = user?.makeHidden(['email', 'phone']).toMap();

// email and phone are hidden for this instance
```

`makeHidden`, `makeVisible` and `append` return the same model and change it: every later `toMap()` or `toJson()` on that instance keeps the change, while other instances are untouched.

> [!WARNING]
> A name in the model's own `visible` list wins over every hidden name. `toMap()` removes each model-level `visible` name from the hidden set before it serializes, and `makeHidden` only edits the runtime sets, so `makeHidden(['password'])` does not hide `password` on a model whose `visible` lists it. The same removal applies to a model-level `hidden` entry that is also in `visible`. Take the name out of `visible` to stop serializing it.

### Making Hidden Attributes Visible

Show attributes the model hides by default:

```dart
final user = await User.find(1);
final array = user?.makeVisible(['password']).toMap();

// password is included for this instance
```

<a name="appending-attributes"></a>
## Appending Attributes

Name attributes that `toMap()` must include even when the model's `visible` whitelist leaves them out:

```dart
class User extends Model {
  @override
  List<String> get visible => ['id', 'name'];

  @override
  List<String> get appends => ['is_admin'];
}
```

An appended name is read with `getAttribute`, so it is included only when the attribute exists and is not `null`, and a hidden attribute is never appended. A Dart getter such as `bool get isAdmin` is not called: Dart has no reflection, so to serialize a computed value, store it with `setAttribute` first.

The stored value is a real attribute of the model, not an output-only field: `toArray()` is `toMap()`, so a later `save()` includes it in the payload it sends to the API and the local store. Build output-only values on a separate map when the backend must not receive them.

```dart
final user = await User.find(1);
user?.setAttribute('is_admin', true);
print(user?.toMap());

// {
//   'id': 1,
//   'name': 'John Doe',
//   'is_admin': true,    // Appended
// }
```

### Runtime Appends

Append additional attributes on one model instance:

```dart
final user = await User.find(1);
final array = user?.append(['avatar_url']).toMap();
```

<a name="api-response-example"></a>
## API Response Example

Combine serialization options for a clean API payload:

```dart
final users = await User.all();

final payload = users
    .map((user) => user.makeHidden(['password', 'remember_token']).toMap())
    .toList();
```

`makeHidden` only hides these names when the model's `visible` list does not name them (see [Hiding Attributes](#hiding-attributes)). With no `visible` list on `User`, this returns:

```json
[
  {
    "id": 1,
    "email": "john@example.com",
    "first_name": "John",
    "last_name": "Doe"
  }
]
```

> [!TIP]
> Always hide sensitive attributes like passwords and API keys at the model level using the `hidden` property.

<a name="related-documentation"></a>
## Related Documentation

- [Getting Started](./getting-started.md)
- [Mutators & Casting](./mutators.md)
