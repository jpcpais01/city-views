# City Views

A cozy, toy-like 3D city builder for Android, made with Godot 4 (GDScript, Mobile renderer).

Draw streets and paint where the town should grow, on one continuous, reshapeable island
with no tile grid. The town lays out its own side streets, lots and houses in the style of
each quarter, with shops on busy streets, parks, squares and churches. Day turns to night,
windows glow, cars and townsfolk potter around, and up to four friends can build on the
same island online.

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
- `tests/island_shot.tscn` renders a screenshot of the island (see the `CV_*` options at the top of `tests/island_shot.gd`).
