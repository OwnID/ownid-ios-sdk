# Configuration

Use this reference to initialize OwnID iOS SDK v4 during client app startup. It
covers startup placement, configuration sources, app ID, environment, region,
root URL, language, and logging.

Primary public docs: `../../../../docs/setup/configuration.md`.

## Contents

- [Source Of Truth](#source-of-truth)
- [Integration Task Boundary](#integration-task-boundary)
- [Startup Placement](#startup-placement)
- [Choose One Configuration Source](#choose-one-configuration-source)
- [Configuration Values](#configuration-values)
- [Environment And Tenant Guardrails](#environment-and-tenant-guardrails)
- [Language](#language)
- [Logging](#logging)
- [Minimal Review Checklist](#minimal-review-checklist)

## Source Of Truth

- Public API contracts and comments: `OwnID`, `OwnIDConfiguration`,
  `OwnIDConfigurationBuilder`, `OwnIDJSONConfigurationBuilder`,
  `OwnIDFileConfigurationBuilder`, `OwnIDLogger`, and
  `LanguageTagsProvider`.

## Public Docs And Examples

- Public setup docs: `../../../../README.md`,
  `../../../../docs/README.md`, and
  `../../../../docs/setup/configuration.md`.
- Demo startup examples: `../../../../Demo/DemoBase/App/DemoBaseApp.swift` and
  `../../../../Demo/DemoAdvanced/App/DemoAdvancedApp.swift`.

Use SDK internals only to confirm public API behavior. Treat public APIs,
public API comments, and package metadata as the client integration contract;
use public docs and demos as guidance/examples.

## Integration Task Boundary

Configuration work answers these questions:

- Where in app startup should `OwnID` be initialized?
- Which public initialization source should the app use?
- Where do the OwnID application ID and environment-specific values come from?
- Which public values are required or optional?
- Should language or logging be configured?

## Startup Placement

Initialize OwnID once during normal app startup, before using any SDK
functionality. In a SwiftUI app this is usually the `App.init()` path. In a
UIKit lifecycle app this is usually
`application(_:didFinishLaunchingWithOptions:)` or the app's existing startup/DI
module called from there.

Rules:

- Use the app's existing configuration source and dependency-injection pattern.
- Configure `OwnID.logger { ... }` before initialization when startup or config
  diagnostics are needed.

DemoBase and DemoAdvanced both initialize from JSON in `App.init()`. Use those
demos as JSON startup examples.

## Choose One Configuration Source

All public initialization sources create the same SDK configuration. Choose the
source that matches the host app's existing environment-management model.

Use programmatic configuration when values already live in build settings,
xcconfig, dependency injection, or the app's startup configuration object:

```swift
import OwnIDCore

OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"
}
```

Use JSON when the app already stores, receives, or generates OwnID configuration
as a JSON string. The demos pass JSON through `Info.plist` from `.xcconfig`
values:

```swift
OwnID.initializeFromJSON { configuration in
    configuration.json = ownIDConfigJSON
}
```

Use file configuration when OwnID config is bundled as a plist. The default file
is `OwnIDConfig.plist` in the main bundle:

```swift
OwnID.initializeFromFile { configuration in
    // Optional; defaults to OwnIDConfig.plist in Bundle.main.
    configuration.fileURL = Bundle.main.url(
        forResource: "OwnIDConfig",
        withExtension: "plist"
    )
}
```

Use one configuration source for the app startup path.

## Configuration Values

`appID` is required. All other public values are optional.

- `appID`: OwnID application ID from the OwnID Console. It must be non-empty and
  alphanumeric. JSON and plist accept `appID` or `appId`.
- `env`: OwnID environment. Defaults to `.prod`; use `.uat` only for UAT
  tenants. JSON and plist values are decoded case-insensitively, for example
  `"prod"` or `"uat"`.
- `region`: OwnID data-residency region. Defaults to `.us`; use `.eu` only for
  EU tenants. JSON and plist values are decoded case-insensitively.
- `rootURL`: Optional custom HTTPS OwnID server-routing root supplied by OwnID.
  JSON and plist accept `rootURL` or `rootUrl`. The SDK normalizes it by
  stripping query and fragment values, then routes API calls through `/api`,
  user-journey event API calls through `/api/event/journey`, diagnostic server
  logs through `/events`, localization through `/i18n`, and hosted SDK/WebBridge
  content through `/sdk/<appID>`. Do not include those path segments in the
  configured root.
- `languages`: Optional explicit BCP 47 language-tag list. Omit it to keep the
  current language mode; on fresh startup this means automatic system language
  tracking.

Unknown JSON and plist keys are ignored. Invalid builders, invalid or empty
JSON, missing or unreadable files, empty files, and invalid values are logged and
leave the current SDK runtime unchanged.

## Environment And Tenant Guardrails

Treat environment selection as tenant configuration, not business logic:

- Get `appID`, `env`, `region`, and any `rootURL` from the OwnID tenant setup or
  approved app configuration.
- Keep production and UAT values separated using the app's existing scheme,
  xcconfig, Info.plist, build-setting, or configuration system.
- Prefer the app's existing non-source configuration path for private tenant
  values.
- Use the host app's existing secure remote-config startup path when OwnID
  config is fetched remotely; define failure behavior before changing startup.

OwnID configuration should contain only tenant and startup values. Keep
passwords, access tokens, provider tokens, and session payloads out of
configuration files, plist values, logs, and comments.

## Language

By default, OwnID follows `Locale.preferredLanguages`. System language changes
are observed while the SDK remains in automatic mode.

Use a non-empty `languages` array during initialization only when the app must
force OwnID UI text to a specific language list:

```swift
OwnID.initialize { configuration in
    configuration.appID = "<OWNID_APP_ID>"
    configuration.languages = ["en-US"]
}
```

Use `OwnID.setLanguage(...)` for a later language switch:

```swift
OwnID.setLanguage(["en-US", "fr-FR"])
```

Pass an empty array to return to automatic system language tracking:

```swift
OwnID.setLanguage([])
```

Rules:

- Tags should be BCP 47 language tags.
- Passing a non-empty `languages` array during initialization or calling
  `OwnID.setLanguage(...)` with a non-empty array switches the process from
  automatic system language tracking to the explicit list.
- Omitting `languages` during initialization does not clear an existing explicit
  language override.
- Passing an empty array keeps or restores automatic system language tracking.
- Calling `OwnID.setLanguage(...)` before successful initialization is a no-op.

## Logging

SDK-wide logging is optional and is not installed by default. Configuration
build failures can still use the temporary default logger. Configure logging
before initialization if you need logs for configuration or
startup HTTP setup.

```swift
import OwnIDCore

OwnID.logger { logger in
    logger.level = .warn
    logger.category = "OwnID"
}
```

Use a custom sink only when the app already has a logging pipeline:

```swift
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

Rules:

- The most recent `OwnID.logger { ... }` call replaces the previous logger.
- Use `.debug` or `.verbose` only for a local diagnostic run or a time-boxed
  diagnostic task.
- Keep production logging at `.warn`, `.error`, or `.off` unless the app's
  support process explicitly requires more detail.
- Keep passwords, OwnID access tokens, provider tokens, session payloads, full
  auth responses, and personally identifying login IDs out of logs.

## Minimal Review Checklist

Before finishing configuration work in a host app, verify by inspection:

- OwnID is initialized before any SDK use.
- The startup location is owned by the app's existing initialization path.
- Exactly one configuration source is used for the app startup path.
- `appID`, `env`, `region`, and `rootURL` come from an approved tenant/config
  source.
- Language mode matches the app's intent: automatic tracking, explicit override,
  or reset to automatic.
- Logging level and sink match the app's environment and privacy policy.
