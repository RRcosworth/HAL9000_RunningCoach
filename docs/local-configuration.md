# Local Configuration

Private machine-specific values live in `Config/Local.xcconfig`.

`Config/Local.xcconfig` is ignored by Git. Keep real personal values there and never commit it.

## Setup

Copy the template if the local file does not exist:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Then fill the values you need:

```xcconfig
HAL9000_DEVELOPMENT_TEAM =
HAL9000_BUNDLE_IDENTIFIER = com.hal9000.runnercoach
HAL9000_PROFILE_DISPLAY_NAME = Runner
HAL9000_BACKEND_BASE_URL =
HAL9000_USE_LOCAL_SERVER = NO
HAL9000_LOCAL_SERVER_HOST = 127.0.0.1
HAL9000_LOCAL_SERVER_PORT = 5051
```

## Fields

`HAL9000_DEVELOPMENT_TEAM`: Apple Developer Team ID. Required when installing on a real iPhone.

`HAL9000_BUNDLE_IDENTIFIER`: App bundle identifier. Keep it stable after installing the app, otherwise iOS treats the next build as a different app.

`HAL9000_PROFILE_DISPLAY_NAME`: Display name shown on the Profile tab.

`HAL9000_BACKEND_BASE_URL`: Remote backend URL for Training data, without a trailing slash. Leave empty if you do not use a remote backend.

`HAL9000_USE_LOCAL_SERVER`: Set to `YES` to use the local backend host and port instead of the remote backend URL.

`HAL9000_LOCAL_SERVER_HOST`: Local backend host, usually `127.0.0.1` for Simulator. For a real iPhone, use your Mac's LAN IP if the backend runs on your Mac.

`HAL9000_LOCAL_SERVER_PORT`: Local backend port.

Intervals.icu API keys are not stored here. Enter them inside the app so they are not baked into builds or committed to GitHub.
