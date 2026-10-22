# Chess Yetu (Flutter, Android)

Mobile client for the Chess Yetu API: sign in, play the computer, play a friend by code, and rated quick match.

    flutter pub get
    flutter run                      # emulator or phone; web with `-d chrome` needs the API's CORS_ORIGINS to allow it

The server address defaults to `http://10.0.2.2:8780` on the Android emulator (the Docker API on the host) and
`http://localhost:8780` elsewhere. On a real phone, tap the plug icon in the lobby and enter your PC's LAN address,
e.g. `http://192.168.1.20:8780`.

    flutter analyze && flutter test
