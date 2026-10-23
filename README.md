# City Views

A cozy, toy-like 3D city builder for Android, made with Godot 4 (GDScript, Mobile renderer).

Paint roads, homes, shops, offices and parks on a procedurally generated island. Buildings
read their surroundings: they face the street, join into terraced rows, take seaside or
hillside styles and grow taller as the town thrives. Day turns to night, windows glow,
cars potter around and up to four friends can build on the same island online.

## Play
Every merge to `main` builds a signed APK and publishes it on the
[Releases page](../../releases/latest). Download `CityViews.apk` on your phone and open it.

## Online features (Firebase)
Online co-op rooms and cloud saves use Firebase Authentication (anonymous + email/password)
and the Realtime Database, over REST. To enable them, add two repository secrets:

- `FIREBASE_API_KEY`: the Web API key from Firebase project settings
- `FIREBASE_DATABASE_URL`: e.g. `https://your-project-default-rtdb.europe-west1.firebasedatabase.app`

Then in the Firebase console enable **Anonymous** and **Email/Password** sign-in and paste
`database.rules.json` into the Realtime Database rules.

## Signing
CI signs with `android/release.keystore` unless the secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_USER` and `ANDROID_KEYSTORE_PASSWORD` are set.

## Development
- `godot --headless --path . tests/logic_test.tscn` runs the logic checks.
- `tests/gallery.tscn` and `tests/shot.tscn` render screenshots of every tile type / a demo town.
