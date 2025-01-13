# OwnID iOS SDK - Advanced Configuration

The OwnID iOS SDK offers multiple configuration options:

## Table of contents

* [Before You Begin](#before-you-begin)
* [Logging Events](#logging-events)
* [OwnID Environment](#ownid-environment)
* [OwnID Region](#ownid-region)
* [OwnID SDK Language](#ownid-sdk-language)
* [Redirection URI Alternatives](#redirection-uri-alternatives)
* [Manually Invoke OwnID Flow](#manually-invoke-ownid-flow)

## Before You Begin

The configuration options listed here are part of OwnID Code iOS SDK. Check [documentation](../README.md) to be sure that it's available to the type of integration you use.

## Logging Events

OwnID SDK has a Logger that is used to log its events. The default OwnID Logger implementation simply relays logs to os.Logger. To use a custom Logger, implement the `LoggerProtocol`, then specify your custom logger class instance and/or custom tag using this method:

```swift
OwnID.CoreSDK.logger.setLogger(CustomLogger(), customTag: "CustomTag")
```

By default, logging is disabled. To enable logging, set `OwnID.CoreSDK.logger.isEnabled = true`.

Logging can also be enabled in configure function by adding the optional `enableLogging` parameter

```swift
OwnID.CoreSDK.configure(appID: "...", enableLogging: true)
```

Alternatively, you can enable the logging from the configuration file `OwnIDConfiguration.plist` by adding the optional `EnableLogging` parameter:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>OwnIDAppID</key>
    <string>...</string>
    <key>EnableLogging</key>
    <true/>
</dict>
</plist>
```

> [!IMPORTANT]
> It is strongly advised to disable logging in production builds.

## OwnID Environment

By default, the OwnID uses production environment for `appId` specified in configuration. You can set different environment. Possible options are: `uat`, `staging` and `dev`. Use `OwnIDEnv` key in `OwnIDConfiguration.plist` to specify required non-production environment:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>OwnIDAppID</key>
    <string>...</string>
    <key>OwnIDEnv</key>
    <string>uat</string>   
</dict>
</plist>
```

## OwnID Region

 By default, OwnID SDK connects to the datacenter in US region. However, if you are using the datacenter in EU region, you need to specify this using the `OwnIDRegion` key in `OwnIDConfiguration.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>OwnIDAppID</key>
    <string>...</string>
    <key>OwnIDRegion</key>
    <string>eu</string>   
</dict>
</plist>
```

## OwnID SDK Language

By default, SDK uses language TAGs list (well-formed [IETF BCP 47 language tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language)) based on the device locales set by the user in system. You can override this behavior and set the OwnID SDK language TAGs list manually. There are two ways to do so:

Optionally provide list of supported languages as `supportedLanguages` parameter.
```swift
OwnID.CoreSDK.configure(userFacingSDK: DemoApp.info(), supportedLanguages: ["he"])
``` 

Set language TAGs list directly:
```swift
OwnID.CoreSDK.setSupportedLanguages(["he"])
```

> [!NOTE]
> In case both methods are utilized, the SDK follows this priority:
> 
> 1. The list from the `setSupportedLanguages` takes precedence if it's set.
> 2. Then, the list from the `supportedLanguages` value in `configure` function is used if it's set'.
> 3. Finally, the list from device locales is employed.

## Redirection URI Alternatives

> [!IMPORTANT]
> Redirection URI is required only if the OwnID flow involves the OwnID Web App.

The redirection URI determines where the user lands once they are done using their browser to interact with the OwnID Web App. You need to open your project and create a new URL type that corresponds to the redirection URL specified in `OwnIDConfiguration.plist`. 

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>OwnIDAppID</key>
    <string>...</string>
    <key>OwnIDRedirectionURL</key>
    <string>com.myapp.demo://myhost</string>
</dict>
</plist>
```

In Xcode, go to **Info > URL Types**, and then use the **URL Schemes** field to specify the redirection URL. For example, if the value of the `OwnIDRedirectionURL` key is `com.myapp.demo://myhost`, then you could copy `com.myapp.demo` and paste it into the **URL Schemes** field.

## Manually Invoke OwnID Flow
As an alternative to using the OwnID button, you can create a custom view to trigger the same functionality. Essentially, this will mirror the behavior of OwnIDViewModel, but with your custom view. To implement this, create a `PassthroughSubject` and send a value on the button press. In your ViewModel, make the `OwnIDViewModel` subscribe to this newly created publisher.

```swift
// ...
var body: some View {
    CustomButton() {
        viewModel.handleCustomButtonAction()
    }
}
// ...

final class MyLogInViewModel: ObservableObject {
    @Published var loginId = ""
     
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    private let resultPublisher = PassthroughSubject<Void, Never>()
    
    init() {
        ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: Login(),
                                                            loginIdPublisher: $loginId.eraseToAnyPublisher())
        ownIDViewModel.subscribe(to: resultPublisher.eraseToAnyPublisher())
    }
    
    func handleCustomButtonAction() {
        resultPublisher.send()
    }
    
    //...
}
```

Additionally you can reset view by calling `ownIDViewModel.resetDataAndState()`.
