# AI Scientific Calculator (Flutter)

A Flutter (Android, iOS, desktop) version of the `McpAi` Next.js app. It has two parts:

- **Calculator.** A scientific keypad that runs **fully offline**. The engine is a pure-Dart port of
  the web app's TypeScript engine (tokenizer → recursive-descent parser → AST → decimal evaluator).
  It produces the same result string or error code on the spec's test vectors and on 3,192
  generated expressions (see [Engine parity](#engine-parity)).
- **AI chat.** A client of the McpAi server's `POST /api/chat`. The server runs the AI model and the
  MCP calculator tools; the app contains no AI keys. Answers stream in with tool activity and a
  "✓ Verified by MCP tool" badge.

The server address comes from `.env` at build time. There is no settings screen.

## Requirements

- Flutter stable 3.47 or later (Dart 3.13 or later). Check with `flutter --version`.
- A running McpAi server, for example the deployment at `https://mcpai-76u1.onrender.com`.
- Android: Android Studio or the SDK. iOS: Xcode (macOS only).

## Configure with `.env`

```sh
cp .env.example .env      # then edit .env
```

| Key | Meaning |
| --- | --- |
| `API_BASE_URL` | The McpAi server. Release builds need `https://`. Empty means the local dev server `http://127.0.0.1:3000`. |
| `API_TOKEN` | Optional. Sent as `Authorization: Bearer <token>` once the server adds authentication. |

`.env` is git-ignored. Flutter only reads it when you pass it explicitly:

```sh
flutter run --dart-define-from-file=.env
flutter build apk --release --dart-define-from-file=.env
```

The values are compiled into the app, so changing the server means building a new APK.

## Develop against a local server

Run `npm run dev` in `McpAi/` (it listens on `127.0.0.1:3000`) and leave `API_BASE_URL` empty.

| Target | Steps |
| --- | --- |
| iOS simulator / desktop | `flutter run --dart-define-from-file=.env` |
| Android emulator | `adb reverse tcp:3000 tcp:3000` first (again after every emulator restart) |

The local server accepts only `Host: 127.0.0.1` or `localhost`, so **don't use `10.0.2.2`**.
Cleartext HTTP is allowed in **debug builds only**: the Android
[`network_security_config`](android/app/src/debug/res/xml/network_security_config.xml) lives in the
`debug` source set, and iOS Debug uses [`Info-Debug.plist`](ios/Runner/Info-Debug.plist) with an ATS
exception (`test/platform_config_test.dart` keeps it in sync with `Info.plist`).

## Deploy: publish the APK on GitHub Releases

[`.github/workflows/release.yml`](.github/workflows/release.yml) runs analyze and tests, builds a
signed APK, and attaches it to a GitHub Release whenever you push a tag such as `v1.0.0`. GitHub
can't see your `.env`, so the workflow builds its own from repository secrets.

1. **Create a signing key** (once). Keep the file and passwords safe: if you lose them, users can't
   install updates over the old app.

   ```sh
   keytool -genkeypair -v -keystore android/upload-keystore.jks -keyalg RSA -keysize 2048 \
     -validity 10000 -alias upload
   ```

   For local release builds, also create `android/key.properties` (git-ignored):

   ```properties
   storeFile=upload-keystore.jks
   storePassword=<your store password>
   keyAlias=upload
   keyPassword=<your key password>
   ```

   Without it, local release builds are signed with the debug key: fine for testing, never publish
   those.

2. **Push the project to GitHub** (`.env`, `key.properties` and `*.jks` are git-ignored):

   ```sh
   git init && git add . && git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/<you>/<repo>.git
   git push -u origin main
   ```

3. **Add repository secrets** (Settings → Secrets and variables → Actions):

   | Secret | Value |
   | --- | --- |
   | `API_BASE_URL` | `https://mcpai-76u1.onrender.com` |
   | `ANDROID_KEYSTORE_BASE64` | `base64 -w0 android/upload-keystore.jks` (Git Bash), or `[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\upload-keystore.jks"))` (PowerShell) |
   | `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | From step 1 (alias `upload`) |
   | `API_TOKEN` | Optional |

4. **Release:** `git tag v1.0.0 && git push origin v1.0.0`. After a few minutes the APK appears
   under the repository's **Releases** as `ai-calculator-v1.0.0.apk`. The tag (without `v`) becomes
   the app's version name. For the next version, push `v1.0.1` and so on.

Users download the APK on their phone and install it (Android asks them to allow installs from the
browser). iOS: `flutter build ipa --release --dart-define-from-file=.env` on macOS with signing
configured in Xcode.

### About the server

- On Render's free tier the server sleeps after about 15 minutes without traffic and takes 30–60 s
  to wake up. The app waits: chat requests have no read timeout and the status check waits up to
  60 s.
- The server has no authentication, so anyone who finds the URL can use it (and your OpenRouter
  quota). It also allows only 2 AI requests at a time across all users; others get a "busy"
  message.

## How the chat works

- The request body is `{"messages":[{"role":"user"|"assistant","content":"…"}]}`. It contains the
  completed turns plus the new prompt, trimmed to the last 20 messages and always starting with a
  user message. Each message is at most 2,000 characters.
- The response is NDJSON, read incrementally ([`lib/chat/chat_api.dart`](lib/chat/chat_api.dart)).
  Lines may span chunks; malformed lines and unknown event types are ignored. Events are parsed into
  sealed classes in [`lib/chat/chat_models.dart`](lib/chat/chat_models.dart).
- 10 s connect timeout and **no read timeout** while streaming. If no event arrives for 15 s, the
  bubble says "The model may still be loading".
- **Stop** closes the HTTP connection, and the server stops its work.
- Non-200 responses are shown using the server's `message`. Message contents are never logged.

Badges: `✓ Verified by MCP tool: <names>`; `⚠ The MCP tool returned an error`; `⚠ No calculator
tool was used`; `AI unavailable — computed directly via MCP`. The status pills come from
`GET /api/health`; tap one to re-check. The sun/moon button in the top bar switches between the
dark (default) and light themes.

## Calculator engine

Code is in [`lib/calculator/`](lib/calculator/): `tokenizer.dart`, `parser.dart`,
`evaluator.dart`, `scientific.dart`, `format.dart`, `errors.dart` and `decimal.dart`.

- `decimal.dart` is a small BigInt-backed decimal type that reproduces the web app's decimal.js
  setup: 34 significant digits, half-even rounding, exact literals, and decimal.js `toString`. The
  `decimal` package was not used because it computes exact rationals: it can't evaluate series for
  sin/ln/exp, and its rounding differs from the original's.
- Transcendental functions use series at 60 working digits, then round to 34 digits like
  decimal.js. Results are shown with 15 significant digits.

### Engine parity

`test/fixtures/engine_parity.json` holds results produced by the original TypeScript engine for the
spec's vectors plus 3,000 seeded random expressions; `test/engine_parity_test.dart` requires exact
matches. To regenerate it (reads `McpAi/`, never modifies it):

```sh
MCPAI_DIR=../McpAi node ../McpAi/node_modules/tsx/dist/cli.mjs tool/gen_engine_parity.mts test/fixtures/engine_parity.json
```

Known difference: in McpAi, decimal.js `tanh` effectively never returns for huge arguments
(`tanh(1e7)` runs for more than 90 s). The Dart engine returns ±1 immediately for |x| > 50.

## Tests

```sh
flutter analyze
flutter test
```

| File | Covers |
| --- | --- |
| `test/calculator_engine_test.dart` | Every test vector from the spec, errors with codes and positions, limits, formatting |
| `test/engine_parity_test.dart` | 3,192 golden cases from the TypeScript engine |
| `test/chat_api_test.dart` | NDJSON decoding (chunk splits, split UTF-8, malformed and unknown lines, error events), request shape and headers, HTTP and network errors, cancellation |
| `test/chat_controller_test.dart` | Streaming state machine: tools, badges, history trimming, Stop, `busy`, unexpected end, slow notice |
| `test/keypad_widget_test.dart` | Keypad input, preview, `=` behavior, ⌫, DEG/RAD, history, keyboard, semantic labels, "Explain with AI" |
| `test/chat_screen_widget_test.dart`, `test/app_shell_widget_test.dart` | Chat UI, badges, Stop, errors, phone layout, accessibility of answers |
| `test/platform_config_test.dart` | Cleartext exceptions exist in debug configurations only |

## Project layout

```
lib/
  main.dart, app.dart, config.dart   startup, theme, responsive shell; config.dart reads .env values
  calculator/                        engine + calculator_controller.dart (keypad state, history)
  chat/                              chat_api.dart, chat_models.dart, chat_controller.dart
  ui/                                calculator_screen.dart, chat_screen.dart, navigation.dart, widgets/
test/                                see above
tool/gen_engine_parity.mts           regenerates the parity fixture from the TypeScript engine
```

## Notes

- `flutter_markdown` (used for assistant replies, as specified) is marked discontinued on pub.dev.
  Its maintained successor, `flutter_markdown_plus`, is a drop-in replacement if needed.
- Calculator history is kept in memory only (last 50 entries).
- Keyboard shortcuts (desktop/tablet): digits, `. + - * / % ^ ! , ( )`, `x` for ×, `s` for √,
  `Enter` or `=` to evaluate, `Backspace`, and `Esc`/`Delete` to clear.
