# SDK Configuration

Initialize OwnID once during app startup before using SDK features.

## Configuration Values

[`appID`](../../OwnIDCore/Sources/OwnIDConfiguration.swift) is required. All other values are optional.

- `appID` (**required**): OwnID application ID from the OwnID Console.
- `env` (**optional**): OwnID environment. Defaults to `.prod`; use `.uat` for UAT tenants.
- `region` (**optional**): OwnID data-residency region. Defaults to `.us`; use `.eu` for EU tenants.
- `rootURL` (**optional**): Custom HTTPS routing root provided by OwnID; it must not contain backslashes. Use it only when OwnID gives you a custom routing URL.
- `languages` (**optional**): Explicit SDK language list. Omit it to keep the current language mode; on fresh startup this means automatic system language tracking.

If configuration fails, the SDK logs the error and keeps the current runtime unchanged. If initialization later succeeds, reacquire namespace handles before starting more work.

## From Code

```swift
import OwnIDCore

OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"
}
```

Most apps only need the application ID. Add optional values only when OwnID provides them for your tenant:

```swift
OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"

    // Optional.
    configuration.env = .uat
    configuration.region = .eu
    configuration.rootURL = "https://auth.example.com"
}
```

## From JSON String

```swift
let ownIDConfigJSON = """
{
  "appId": "<OWNID_APP_ID>",
  "env": "prod",
  "region": "us"
}
"""

OwnID.initializeFromJSON { configuration in
    configuration.json = ownIDConfigJSON
}
```

## From File

`initializeFromFile` reads the supplied `fileURL` directly. If no URL is supplied, it uses `OwnIDConfig.plist` from the app bundle.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>appId</key>
    <string>&lt;OWNID_APP_ID&gt;</string>
    <key>env</key>
    <string>prod</string>
    <key>region</key>
    <string>us</string>
</dict>
</plist>
```

```swift
OwnID.initializeFromFile { configuration in
    // Optional. The default file name is OwnIDConfig.plist.
    configuration.fileURL = Bundle.main.url(
        forResource: "OwnIDConfig",
        withExtension: "plist"
    )
}
```

## Language

By default, the SDK follows `Locale.preferredLanguages`.

Set language during initialization only when the app should force OwnID text to a specific locale:

```swift
OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"
    configuration.languages = ["en-US"]
}
```

You can also update language later:

```swift
OwnID.setLanguage(["en-US", "fr-FR"])
```

Use language codes with optional regions, such as `en` or `en-US`. Pass an empty array to restore automatic language selection.

For UI text customization, see [Localization](../customization/localization.md).

## Logging

Logging is optional and disabled by default. Configure it before initialization when you need SDK logs.

```swift
import OwnIDCore

OwnID.logger { logger in
    logger.level = .warn
    logger.category = "OwnID"
}
```

Use a custom sink when SDK logs should go through your app logging pipeline:

```swift
import OwnIDCore

OwnID.logger { logger in
    logger.level = .debug
    logger.category = "OwnID"
    logger.log { level, className, message, cause in
        appLogger.log(
            "[\(level)] \(className): \(message)",
            error: cause
        )
    }
}
```

Custom sinks are invoked synchronously on the thread that emits each log and may run on any thread. Keep the sink
thread-safe and return promptly; offload blocking I/O or other long-running work to app-owned background execution. Do
not synchronously call OwnID lifecycle or configuration APIs from the sink.

Use `.debug` or `.verbose` only for local development. Keep production logging at `.warn`, `.error`, or `.off` unless your support process requires more detail.

> [!WARNING]
> Do not log passwords, OwnID tokens, provider tokens, or session payloads.
