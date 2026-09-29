# Exporting for Android

The project ships with two export presets in `export_presets.cfg`:

| Preset | Output | Build type | Use |
| --- | --- | --- | --- |
| **Android APK (sideload)** | `build/SpireSprint.apk` | Godot's prebuilt template (no Gradle, no Android SDK build tools needed for export itself) | Testing on devices, sharing the game directly |
| **Android AAB (Google Play)** | `build/SpireSprint.aab` | Gradle build (`gradle_build/export_format = 1`) | Publishing on Google Play |

Both use package `io.github.noswear32.spiresprint` (change `package/unique_name` in **both** presets before
publishing under your own name), **arm64-v8a** only, immersive fullscreen, phone *and* tablet screens, and
request exactly one permission: `VIBRATE` (haptics). There is **no INTERNET permission** — the game is fully
offline (debug builds may add it for remote debugging; release builds do not).

Orientation, scaling and sensors come from `project.godot` (`display/window/handheld/orientation = 4` sensor
landscape, `canvas_items` + `keep_height`, accelerometer and gravity enabled, ETC2/ASTC import enabled). The
Compatibility renderer is used, so the game runs on every OpenGL ES 3.0 device.

## 1. Tools you need

* **Godot 4.3 or newer** (standard build) **and the export templates of exactly the same version**
  (*Editor ▸ Manage Export Templates*, or download `.tpz` and use *Install from File*).
* **JDK 17** (OpenJDK is fine) — `java -version` must report 17.
* **Android SDK** with: platform-tools, command-line tools, a *Build-Tools* and *Platform* version matching your
  Godot version (see the “Exporting for Android” page of the Godot documentation for the current numbers) and
  the NDK/CMake versions it lists (only required for Gradle/AAB builds).
  Point the editor to it in *Editor ▸ Editor Settings ▸ Export ▸ Android ▸ Android SDK Path* and the JDK in
  *Java SDK Path*.

The minimum supported Android version is set by the export template (API 24 = Android 7.0 for current templates).

## 2. Signing keys

Never commit keystores or passwords (`.gitignore` already excludes `*.keystore`, `*.jks`).

**Debug key** (for test installs):

```bash
keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore \
        -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
```

Set it in *Editor Settings ▸ Export ▸ Android ▸ Debug Keystore* (user `androiddebugkey`, password `android`), or
export `GODOT_ANDROID_KEYSTORE_DEBUG_PATH`, `GODOT_ANDROID_KEYSTORE_DEBUG_USER`, `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD`.

**Release key** (for Google Play / signed sideload builds) — keep a backup, losing it means you cannot update the app
(unless you enroll in Play App Signing, which is recommended):

```bash
keytool -v -genkey -keystore spire-sprint-release.keystore -alias spire -keyalg RSA -keysize 2048 -validity 10000
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/secure/path/spire-sprint-release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=spire
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD='…'
```

(The environment variables are read by the command-line export and by the editor; you may also type the values into
the preset's *Keystore* options — but then they end up in `export_presets.cfg`, so prefer the variables.)

## 3. Export from the editor

1. Open `game/project.godot` once and wait for the initial import to finish.
2. *Project ▸ Export…* → choose **Android APK (sideload)** → *Export Project* (use *Export With Debug* for a debug-signed,
   directly installable file).
3. Install: `adb install -r build/SpireSprint.apk`. Watch the log with `adb logcat -s godot`.

## 4. Export from the command line (CI friendly)

```bash
cd game
godot --headless --import                       # first time / after asset changes (builds the .godot cache)
mkdir -p build

# debug-signed APK, installable immediately
godot --headless --export-debug   "Android APK (sideload)" build/SpireSprint-debug.apk

# release APK (needs the release keystore variables above)
godot --headless --export-release "Android APK (sideload)" build/SpireSprint.apk
```

## 5. Google Play bundle (AAB)

1. *Project ▸ Install Android Build Template…* (creates `android/build/` — Gradle project for your Godot version).
   Headless alternative: unzip `android_source.zip` from the export templates folder into `android/build/` and write the
   template version (for example `4.3.stable`) into `android/.build_version`.
2. Export: `godot --headless --export-release "Android AAB (Google Play)" build/SpireSprint.aab`
   (release keystore variables required; the first Gradle run downloads dependencies).
3. Upload the `.aab` in the Play Console. Increase `version/code` (an integer that must grow with every upload) and
   `version/name` in **both presets**, and `application/config/version` in `project.godot` (shown in *About* and stored
   in replays) for every release.

Play Console checklist: content rating questionnaire (no violence, no user-generated content shared online),
*Data safety*: **no data collected, no data shared** (the game never connects to a network), target audience
“everyone”, privacy policy URL (state that everything stays on the device), store listing screenshots (landscape).
Custom characters and replays are only ever exchanged through the system share sheet / file picker chosen by the player.

## 6. Icons and splash

* Launcher icons (`assets/icons/`): `icon_192.png`, adaptive foreground/background/monochrome at 432 × 432 (the
  monochrome layer is used for themed icons on Android 13+). Regenerate with `python3 tools/gen_art.py ui`.
* The boot splash is a solid colour matching the game's background (`boot_splash/bg_color`), followed by the in-game
  logo splash on the very first launch.

## 7. Troubleshooting

| Symptom | Fix |
| --- | --- |
| *“Could not find Android SDK / Java SDK”* | Set both paths in Editor Settings ▸ Export ▸ Android; on CI export `ANDROID_HOME`/`ANDROID_SDK_ROOT` and `JAVA_HOME`. |
| *“No export template found”* / version mismatch | Install templates for **exactly** the editor's version (4.3.stable ≠ 4.3.1.stable). |
| *“Release keystore incorrectly configured”* | Set the `GODOT_ANDROID_KEYSTORE_RELEASE_*` variables, or use `--export-debug`. |
| *“Invalid icon / could not load launcher icons”* | Run `python3 tools/gen_art.py ui` (needs numpy + Pillow) and re-import. |
| Gradle build fails with Java errors | Use JDK 17; delete `android/build/build` and retry. |
| Black screen or crash on very old devices | The game needs OpenGL ES 3.0; check `adb logcat -s godot` for the GPU error. |
| Texture import errors on export | `rendering/textures/vram_compression/import_etc2_astc` must stay **on** (it is). |
| Game starts in portrait | Make sure the export preset was not overridden: orientation comes from `display/window/handheld/orientation = 4`. |
| Saves seem to disappear after reinstall | `user://` is app-private storage; uninstalling removes it (the game has no cloud save). |

## 8. Where the game stores its data

Godot's `user://` folder, i.e. app-private storage on Android, inside `user://spire_sprint/`:
`profile.json` (+ `profile.bak.json`, `profile.tmp.json`, and `profile.corrupt.json` when a repair happened),
`replays/<id>.replay.json` and `characters/<id>.spirechar`. On a debug build the folder can be inspected with
`adb shell run-as io.github.noswear32.spiresprint ls files`.
