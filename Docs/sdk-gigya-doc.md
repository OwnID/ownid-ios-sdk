![OwnIDSDK](logo.svg)


# OwnID Gigya iOS SDK

The OwnID Gigya iOS SDK integrates with Email/Password-based [Gigya Authentication](https://github.com/SAP/gigya-swift-sdk) in an iOS application. The SDK is a client library written in Swift that provides a simple way to add the "Skip Password" feature to the registration and login screens of your native app. For more general information about OwnID SDKs, see [OwnID iOS SDK](../README.md).

## Table of contents
* [Before You Begin](#before-you-begin)
* [Add Package Dependency](#add-package-dependency)
  + [Cocoapods](#cocoapods)
  + [Swift Package Manager](#swift-package-manager)
* [Enable Passkey Authentication](#enable-passkey-authentication)
* [Add Property List File to Project](#add-property-list-file-to-project)
* [Import OwnID Module](#import-ownid-module)
* [Initialize the SDK](#initialize-the-sdk)
  + [Add OwnID WebView Bridge](#add-ownid-webview-bridge)
* [Implement the Registration Screen](#implement-the-registration-screen)
  + [Customize View Model](#customize-view-model)
  + [Add the OwnID View](#add-the-ownid-view)
* [Implement the Login Screen](#implement-the-login-screen)
  + [Customize View Model](#customize-view-model-1)
  + [Add OwnID View](#add-ownid-view)
  + [Social Login and Account linking](#social-login-and-account-linking)
* [Tooltip](#tooltip)
* [Errors](#errors)
* [Advanced Configuration](#advanced-configuration)
  + [Logging Events](#logging-events)
  + [OwnID Environment](#ownid-environment)
  + [OwnID SDK Language](#ownid-sdk-language)
  + [Redirection URI Alternatives](#redirection-uri-alternatives)
  + [Alternative Syntax for Configure Function](#alternative-syntax-for-configure-function)
  + [Button Apperance](#button-apperance)
  + [Manually Invoke OwnID Flow](#manually-invoke-ownid-flow)

---

## Before You Begin
Before incorporating OwnID into your iOS app, you need to create an OwnID application and integrate it with your Gigya project. For step-by-step instructions, see [OwnID-Gigya Integration Basics](gigya-integration-basics.md).

In addition, ensure you have done everything to [add Gigya authentication to your iOS project](https://github.com/SAP/gigya-swift-sdk).

## Add Package Dependency

### Cocoapods

The SDK is distributed via Cocoapods. Use the Cocoapods to add the following package dependency to your project:

```
pod 'ownid-gigya-ios-sdk'
```

The OwnID iOS SDK supports Swift >= 5.1, and works with iOS 14 and above.

### Swift Package Manager

- In Xcode, select File > Swift Packages > Add Package Dependency.
- Follow the prompts using the URL for this repository.

## Enable Passkey Authentication

The OwnID SDK uses passkeys to authenticate users. To enable passkey support for your iOS app, associate your app with a website that your app owns using Associated Domains by following this guide: [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

## Add Property List File to Project

When the application starts, the OwnID SDK automatically reads `OwnIDConfiguration.plist` from the file system to configure the default instance that is created. At a minimum, this PLIST file defines the OwnID App Id - the unique identifier of your OwnID application, which you can obtain from the [OwnID Console](https://console.ownid.com). Create `OwnIDConfiguration.plist` and define the following mandatory parameters:

[Complete example](../Demo/GigyaDemo/OwnIDConfiguration.plist)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>OwnIDAppID</key>
        <string>l16tzgmvvyf5qn</string>
</dict>
</plist>
```
Where:

- The `OwnIDAppID` is the unique AppID, which you can obtain from the [OwnID Console](https://console.ownid.com).

For additional configuration options, including environment configuration, see [Advanced Configuration](#advanced-configuration).

## Import OwnID Module
Once you have added the OwnID package dependency, you need to import the OwnID module so you can access the SDK features. As you implement OwnID in your project, add the following to your source files:

[Complete example](../Demo/GigyaDemo/GigyaDemoApp.swift)
```swift
import OwnIDGigyaSDK
```

## Initialize the SDK
The OwnID SDK must be initialized properly using the `configure()` function, preferably in the main entry point of your app (in the `@main` `App` struct). For example, enter:

[Complete example](../Demo/GigyaDemo/GigyaDemoApp.swift)
```swift
@main
struct ExampleApp: App {
    init() {
        OwnID.GigyaSDK.configure()
    }
}
```

If you did not follow the recommendation for creating the `OwnIDConfiguration.plist` file, you need to specify arguments when calling the `configure` function. For details, see [Alternative Syntax for Configure Function](#alternative-syntax-for-configure-function).

### Add OwnID WebView Bridge
 If you're running Gigya with Screen-Sets and want to utilize the [OwnID iOS SDK WebView Bridge](sdk-webbridge-doc.md), then add `OwnID.GigyaSDK.configureWebBridge()`:

 See [complete example](../Demo/ScreensetsDemo/DemoApp.swift)

 ```swift
 struct DemoApp: App {
    init() {
        OwnID.GigyaSDK.configure(appID: "l16tzgmvvyf5qn")
        OwnID.GigyaSDK.configureWebBridge()
    }
    
    ...
}
 ```

## Implement the Registration Screen
Within a Model-View-ViewModel (MVVM) architecture pattern, adding the Skip Password option to your registration screen is as easy as adding an OwnID view model and subscription to your app's ViewModel layer, then adding the OwnID view to your main View. That's it! When the user selects Skip Password, your app waits for events while the user interacts with the OwnID flow views, then calls a function to register the user once they have completed the Skip Password process.

**Important:** When a user registers with OwnID, a random password is generated and set for the user's Gigya account.

### Customize View Model
The OwnID view that inserts the Skip Password UI is bound to an instance of the OwnID view model. Before modifying your View layer, create an instance of this view model, `OwnID.FlowsSDK.RegisterView.ViewModel`, within your ViewModel layer:

[Complete example](../Demo/GigyaDemo/RegisterViewModel.swift)
```swift
final class MyRegisterViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: <Your Instance Of Gigya>, loginIdPublisher: AnyPublisher<String, Never>)
}
```

Where `loginIdPublisher` provides input that user is typing into loginID field. See example of `@Published` property in demo app.

After creating this OwnID view model, your View Model layer should listen to events from the OwnID Event Publisher, which allows your app to know what actions to take based on the user's interaction. Simply add the following to your existing ViewModel layer to subscribe to the OwnID Event Publisher and respond to events (it can be placed just after the code that creates the OwnID view model instance).

[Complete example](../Demo/GigyaDemo/RegisterViewModel.swift)

```swift
final class MyRegisterViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    
    func createViewModel(loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher) {
      let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: loginIdPublisher)
      self.ownIDViewModel = ownIDViewModel
    }

    init() {
     subscribe(to: ownIDViewModel.eventPublisher)
    }

     func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
       eventsPublisher
           .receive(on: DispatchQueue.main)
           .sink { [unowned self] event in
               switch event {
               case .success(let event):
                   switch event {
                   // Event when user successfully
                   // finishes Skip Password
                   // in OwnID Web App
                   case .readyToRegister:
                     // To pass additional parameters,
                     // such as first name, use
                     // the same approach as in Gigya
                     let nameValue = "{ \"firstName\": \"\(firstName)\" }"
                     let paramsDict = ["profile": nameValue]
                     let params = OwnID.GigyaSDK.Registration.Parameters(parameters: paramsDict)
                     ownIDViewModel.register(registerParameters: params)

                   // Event when OwnID creates Gigya
                   // account and logs in user
                   case .userRegisteredAndLoggedIn:
                     // User is registered and logged in with OwnID

                   case .loading:
                     // Button displays customizable loader
		     
		   case .resetTapped:
 		     // User tapped activeted button. Rest any data if
 		     // needed. 
                   }

               case .failure(let error):
                // Handle OwnID.CoreSDK.Error here
                // For an example of handling an interruption,
                // see Errors section of this doc
               }
           }
           .store(in: &bag)
   }
}
```

**Important:** The OwnID `ownIDViewModel.register` function must be called in response to the `.readyToRegister` event. This `ownIDViewModel.register` function eventually calls the standard Gigya function `createUser(withEmail: password:)` to register the user in Gigya, so you do not need to call this Gigya function yourself.

### Add the OwnID View
Inserting the OwnID view into your View layer results in the OwnID button appearing in your app. The code that creates this view accepts the OwnID view model as its argument.

It is reccomended to set height of button the same as text field and disable text field when OwnID is enabled. 

[Complete example](../Demo/GigyaDemo/RegisterView.swift)
```swift
//Put RegisterView inside your main view, preferably besides password field
var body: some View {
    OwnID.GigyaSDK.createRegisterView(viewModel: viewModel.ownIDViewModel)
}
```

## Implement the Login Screen
The process of implementing your Login screen is very similar to the one used to implement the Registration screen. When the user selects Skip Password on the Login screen and if the user has previously set up OwnID authentication, allows them to log in with OwnID.

Like the Registration screen, you add Skip Password to your application's Login screen by including an OwnID view. In this case, it is `OwnID.LoginView`. This OwnID view has its own view model, `OwnID.LoginView.ViewModel`.

### Customize View Model
You need to create an instance of the view model, `OwnID.LoginView.ViewModel`, that the OwnID login view uses. Within your ViewModel layer, enter:

[Complete example](../Demo/GigyaDemo/LogInViewModel.swift)
```swift
final class MyLogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: <Your Instance Of Gigya>, loginIdPublisher: AnyPublisher<String, Never>)
}
```

 Where `loginIdPublisher` provides input that user is typing into loginID field. See example of `@Published` property in demo app.

After creating this OwnID view model, your View Model layer should listen to events from the OwnID Event Publisher, which allows your app to know what actions to take based on the user's interaction with the Skip Password option. Simply add the following to your existing ViewModel layer to subscribe to the OwnID Event Publisher and respond to events.

[Complete example](../Demo/GigyaDemo/LogInViewModel.swift)
```swift
final class MyLogInViewModel: ObservableObject {
    // MARK: OwnID
    var ownIDViewModel: OwnID.FlowsSDK.LoginView.ViewModel!
    
    func createViewModel(loginIdPublisher: OwnID.CoreSDK.LoginIdPublisher) {
      let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: loginIdPublisher)
      self.ownIDViewModel = ownIDViewModel
    }

     init() {
       subscribe(to: ownIDViewModel.eventPublisher)
     }

     func subscribe(to eventsPublisher: OwnID.LoginPublisher) {
       eventsPublisher
           .receive(on: DispatchQueue.main)
           .sink { [unowned self] event in
               switch event {
               case .success(let event):
                   switch event {
                   // Event when user who previously set up
                   // OwnID logs in with Skip Password
                   case .loggedIn:
                     // User is logged in with OwnID
                     
                   case .loading:
                     // Button displays customizable loader
                   }

               case .failure(let error):
                 // Handle OwnID.CoreSDK.Error here
               }
           }
           .store(in: &bag)
   }
}
```

### Add OwnID View
Inserting the OwnID view into your View layer results in the Skip Password option appearing in your app. When the user selects Skip Password, the SDK opens a sheet to interact with the user. It is recommended that you place the OwnID view, `OwnID.LoginView`, immediately after the password text field. The code that creates this view accepts the OwnID view model as its argument. It is suggested that you pass user's email binding for properly creating accounts.

[Complete example](../Demo/GigyaDemo/LogInView.swift)
```swift
//Put LoginView inside your main view, preferably below password field
var body: some View {
  //...
  OwnID.GigyaSDK.createLoginView(viewModel: viewModel.ownIDViewModel)
  //...
}
```

By default, tooltip popup will appear every time login view is shown.

### Social Login and Account Linking

If you use Gigya [Social Login](https://sap.github.io/gigya-swift-sdk/GigyaSwift/#social-login) feature then you need to handle [Account linking interruption](https://sap.github.io/gigya-swift-sdk/GigyaSwift/#interruptions-handling---account-linking-example) case. To let OwnID do account linking add the parameter `loginType` with value `.linkSocialAccount` to your login view model instance.

```swift
let ownIDViewModel = OwnID.GigyaSDK.loginViewModel(instance: Gigya.sharedInstance(),
                                                  loginIdPublisher: loginIdPublisher,
                                                  loginType: .linkSocialAccount)
```

## Tooltip

The OwnID SDK's `OwnIdButton` by default shows a Tooltip with text "Login with Face ID". 

![OwnID Tooltip UI Example](tooltip_example.png) ![OwnID Tooltip Dark UI Example](tooltip_example_dark.png)

On Registration you can setup the logic of tooltip appearing. By default it appears if the `loginId` text input is valid. Here how you can customize it 

```swift
ownIDViewModel.shouldShowTooltipLogic = false
```

`OwnIdButton` view has parameters to specify tooltip background color, border color, text color, text size, shadowColor and tooltip position `top`/`bottom`/`leading`/`trailing` (default `bottom`). You can change them by setting values in view attributes:

```swift
OwnID.GigyaSDK.createLoginView(viewModel: ownIDViewModel, visualConfig: OwnID.UISDK.VisualLookConfig(tooltipVisualLookConfig: OwnID.UISDK.TooltipVisualLookConfig(backgroundColor: .gray, borderColor: .black, textColor: .white, textSize: 20, tooltipPosition: .top)))
```

By default the tooltip has `zIndex(1)` to be above all other view. But if the OwnID View is inside some Stack and the tooltip is covered by another view it's recommended to set `zIndex(1)` for this stack

 ```swift
HStack {
    OwnID.GigyaSDK.createLoginView(viewModel: ownIDViewModel)
    SecureField("password", text: $password)
}
.zIndex(1)
```

## Errors
All errors from the SDK have an `OwnID.CoreSDK.Error` type. You can use them, for example, to properly ask the user to perform an action.

Here are these errors:

[Complete example](../ownid-core-ios-sdk/Core/Sources/Types/CoreError.swift)
```swift
switch error {
case flowCancelled(let flow):
     print("flowCancelled")
     
 case userError(let errorModel):
     print("userError")
     
 case integrationError(underlying: Swift.Error):
     print("integrationError")
 }
}
```

Where: 

- flowCancelled(flow: FlowType) - Exception that occurs when user cancelled OwnID flow. Usually application can ignore this error. 
- userError(errorModel: UserErrorModel) - Error that is intended to be reported to end user. The userMessage string from UserErrorModel is localized based on OwnID SDK language and can be used as an error message for user. 
- integrationError(underlying: Swift.Error) - General error for wrapping Gigya errors OwnID integrates with.

## Advanced Configuration

### Logging Events

OwnID SDK has a Logger that is used to log its events. You can enable Xcode console & Console.app logging by calling `OwnID.CoreSDK.logger.isEnabled = true`. To use a custom Logger, call `OwnID.CoreSDK.logger.setLogger(CustomLogger(), customTag: "CustomTag")`

### OwnID environment

By default, the OwnID uses production environment for `appId` specified in configuration. You can set different environment. Possible options are: `uat`, `staging` and `dev`. Use `env` key in configuration json to specify required non-production environment:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>OwnIDAppID</key>
        <string>l16tzgmvvyf5qn</string>
        <key>OwnIDEnv</key>
        <string>uat</string>   
</dict>
</plist>
```

### OwnID SDK Language

By default, SDK uses language TAGs list (well-formed [IETF BCP 47 language tag](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Accept-Language)) based on the device locales set by the user in system. You can override this behavior and set the OwnID SDK language TAGs list manually. There are two ways to do so:

Optionally provide list of supported languages of `OwnID.CoreSDK.Languages` as `supportedLanguages` parameter.
```swift
OwnID.GigyaSDK.configure(supportedLanguages: ["he"])
``` 

Set language TAGs list directly:
```swift
OwnID.CoreSDK.setSupportedLanguages(["he"])
```

### Redirection URI Alternatives
The redirection URI determines where the user lands once they are done using their browser to interact with the OwnID Web App. You need to open your project and create a new URL type that corresponds to the redirection URL specified in `OwnIDConfiguration.plist`. 

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
        <key>OwnIDAppID</key>
        <string>4tb9nt6iaur0zv</string>
        <key>OwnIDRedirectionURL</key>
        <string>com.myapp.demo://myhost</string>
</dict>
</plist>
```

In Xcode, go to **Info > URL Types**, and then use the **URL Schemes** field to specify the redirection URL. For example, if the value of the `OwnIDRedirectionURL` key is `com.myapp.demo://myhost`, then you could copy `com.myapp.demo` and paste it into the **URL Schemes** field.

### Alternative Syntax for Configure Function
If you followed the recommendation to add `OwnIDConfiguration.plist` to your project, calling `configure()` without any arguments is enough to initialize the SDK. If you did not follow this recommendation, you can still initialize the SDK with one of the following calls. Remember that these calls should be made within your app's `@main` `App` struct.

* `OwnID.GigyaSDK.configure(plistUrl: plist)` explicitly provides the path to the OwnID configuration file, where `plist` is the path to the file.
* `OwnID.GigyaSDK.configure(appID: String)` explicitly defines the configuration options rather than using a PLIST file. The app id is unique to your OwnID application, and can be obtained in the [OwnID Console](https://console.ownid.com). Additionally, you can use optional parameters and call `OwnID.GigyaSDK.configure(appID: config.OwnIDAppID, redirectionURL: config.OwnIDRedirectionURL, environment: config.OwnIDEnv)` The redirection URL is your app's redirection URL, including its custom scheme.

### Button Apperance
It is possible to set button visual settings by passing `OwnID.UISDK.VisualLookConfig`. Additionally, you can override default behaviour of tooltip appearing or other settings in `OwnID.UISDK.TooltipVisualLookConfig`.
By passing `widgetPosition`, `or` text view will change it's position accordingly. It is possible to modify look & behaviour of loader by modifying default settings of `loaderViewConfig` parameter.

```swift
let config = OwnID.UISDK.VisualLookConfig(buttonViewConfig: .init(iconColor: .red, shadowColor: .cyan),
                                          tooltipVisualLookConfig: .init(borderColor: .indigo, tooltipPosition: .bottom),
                                          loaderViewConfig: .init(spinnerColor: .accentColor, isSpinnerEnabled: false))
OwnID.GigyaSDK.createLoginView(viewModel: ownIDViewModel, visualConfig: config)
```

### Manually Invoke OwnID Flow
As alternative to OwnID button it is possible to use custom view to call functionality. In a nutshell, here it is the same behaviour from `ownIDViewModel`, just with your custom view provided.

Create simple `PassthroughSubject`. After you created custom view, on press send void action through this `PassthroughSubject`. In your `viewModel`, make `ownIDViewModel` to subscribe to this newly created publisher.

```swift
ownIDViewModel.subscribe(to: customButtonPublisher.eraseToAnyPublisher())
```

Additionally you can reset view by calling `ownIDViewModel.resetState()`.
