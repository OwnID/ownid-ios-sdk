# OwnID Core iOS SDK - Custom Integration

The OwnID iOS SDK is a client library offering a secure and passwordless login alternative for your iOS applications. It leverages [Passkeys](https://www.passkeys.com) to replace conventional passwords, fostering enhanced authentication methods.

This document describes the way to integrate and use OwnID Core iOS SDK with your identity platform using OwnID Integration component. The alternative way is [Direct Integration](sdk-direct-integration.md).

For more general information about OwnID SDKs, see [OwnID iOS SDK](../README.md).

## Table of contents
* [Before You Begin](#before-you-begin)
* [Add Package Dependency](#add-package-dependency)
  + [Cocoapods](#cocoapods)
  + [Swift Package Manager](#swift-package-manager)
* [Enable Passkey Authentication](#enable-passkey-authentication)
* [Add Property List File to Project](#add-property-list-file-to-project)
* [Import OwnID Module](#import-ownid-module)
* [Initialize the SDK](#initialize-the-sdk)
* [Create OwnID Integration Component](#create-ownid-integration-component)
* [Implement the Registration Screen](#implement-the-registration-screen)
  + [Add the OwnID View](#add-the-ownid-view)
  + [Customize View Model](#customize-view-model)
* [Implement the Login Screen](#implement-the-login-screen)
  + [Add OwnID View](#add-ownid-view)
  + [Customize View Model](#customize-view-model-1)
* [Tooltip](#tooltip)
* [Errors](#errors)
* [Alternative Syntax for Configure Function](#alternative-syntax-for-configure-function)
* [Button Appearance](#button-appearance)

## Before You Begin

Before incorporating OwnID into your iOS app, you need to create an OwnID application in [OwnID Console](https://console.ownid.com) and integrate it with your identity platform. For details, see [OwnID documentation](https://docs.ownid.com/introduction).

## Add Package Dependency

### Cocoapods

The SDK is distributed via Cocoapods. Use the Cocoapods to add the following package dependency to your project:

```
pod 'ownid-core-ios-sdk'
```

### Swift Package Manager

- In Xcode, select File > Swift Packages > Add Package Dependency.
- Follow the prompts using the URL for this repository.

The OwnID iOS SDK supports Swift >= 5.1, and works with iOS 14 and above.

## Enable Passkey Authentication

The OwnID SDK uses passkeys to authenticate users. 

> [!IMPORTANT]
>
> To enable passkey support for your iOS app, associate your app with a website that your app owns using Associated Domains by following this guide: [Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

## Add Property List File to Project

When the application starts, the OwnID SDK automatically reads `OwnIDConfiguration.plist` from the file system to configure the default instance that is created. At a minimum, this PLIST file defines the OwnID App Id - the unique identifier of your OwnID application, which you can obtain from the [OwnID Console](https://console.ownid.com). Create `OwnIDConfiguration.plist` and define the following mandatory parameters:

[Complete example](../Demo/IntegrationDemo/OwnIDConfiguration.plist)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>OwnIDAppID</key>
  <!--Replace with your App Id-->
  <string>gephu342dnff2v</string>
</dict>
</plist>
```

For additional configuration options, including environment configuration, see [Advanced Configuration](sdk-advanced-configuration.md).

## Import OwnID Module
Once you have added the OwnID package dependency, you need to import the OwnID module so you can access the SDK features. As you implement OwnID in your project, add the following to your source files:

[Complete example](../Demo/IntegrationDemo/IntegrationDemoApp.swift)
```swift
import OwnIDCoreSDK
```

## Initialize the SDK
The OwnID SDK must be initialized properly using the `configure(userFacingSDK:supportedLanguages:)` function, preferably in the main entry point of your app (in the `@main` `App` struct). For example, enter:

[Complete example](../Demo/IntegrationDemo/IntegrationDemoApp.swift)
```swift
@main
struct ExampleApp: App {
    init() {
        let info: OwnID.CoreSDK.SDKInformation = (..., ...) //add you info here
        OwnID.CoreSDK.shared.configure(userFacingSDK: info, supportedLanguages: .init(rawValue: Locale.preferredLanguages))
    }
}
```
If you did not follow the recommendation for creating the `OwnIDConfiguration.plist` file, you need to specify arguments when calling the `configure` function. For details, see [Alternative Syntax for Configure Function](#alternative-syntax-for-configure-function).

### Create OwnID Integration Component

To create your OwnID integration component, provide a custom implementation of the `RegistrationPerformer` protocol and add `register` method with your logic.

[Complete example](../Demo/IntegrationDemo/AuthPerformer.swift)
```swift
final class CustomRegistration: RegistrationPerformer {
    func register(configuration: OwnID.FlowsSDK.RegistrationParameters, parameters: RegisterParameters) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        let ownIdData = configuration.payload.dataContainer.rawDataForCustomFlow()
        return //Add code that registers user in your identity platform and set OwnID Data to user profile
    }
}
```

Also, provide a custom implementation of the `LoginPerformer` protocol and add `login` method with your logic.

[Complete example](../Demo/IntegrationDemo/AuthPerformer.swift)
```swift
final class CustomLoginPerformer: LoginPerformer {
    func login(payload: OwnID.CoreSDK.Payload,
               email: String) -> AnyPublisher<OperationResult, OwnID.CoreSDK.Error> {
        let ownIdData = configuration.payload.dataContainer.rawDataForCustomFlow()
        return //Add code that log in user in your identity platform using data
    }
}
```

## Implement the Registration Screen
Within a Model-View-ViewModel (MVVM) architecture pattern, adding the Skip Password option to your registration screen is as easy as adding an OwnID view model and subscription to your app's ViewModel layer, then adding the OwnID view to your main View. That's it! When the user selects Skip Password, your app waits for events while the user interacts with the OwnID flow views, then calls a function to register the user once they have completed the Skip Password process.

### Add the OwnID View
Inserting the OwnID view into your View layer results in the OwnID button appearing in your app. The code that creates this view accepts the OwnID view model as its argument.

It is recommended to set height of button the same as text field and disable text field when OwnID is enabled.

[Complete example](../Demo/IntegrationDemo/RegisterView.swift)
```swift
//Put RegisterView inside your main view, preferably besides password field
var body: some View {
    OwnID.FlowsSDK.RegisterView(viewModel: ownIDViewModel)
}
```

![how it looks like](skip_button_design.png) ![how it looks like](skip_button_design_dark.png)

For additional OwnIDButton UI customization see [Button UI customization](#button-appearance).

### Customize View Model
The OwnID view that inserts the Skip Password UI is bound to an instance of the OwnID view model. Before modifying your View layer, create an instance of this view model, `OwnID.FlowsSDK.RegisterView.ViewModel`, within your ViewModel layer with `CustomRegistration` and `CustomLogin` you created earlier:

[Complete example](../Demo/IntegrationDemo/RegisterViewModel.swift)
```swift
final class MyRegisterViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: CustomRegistration(),
                                                               loginPerformer: CustomLogin(),
                                                               loginIdPublisher: loginIdPublisher)
}
```

Where `loginIdPublisher` provides input that user is typing into loginID field. See example of `@Published` property in demo app.

After creating this OwnID view model, your View Model layer should listen to integration events from the OwnID Event Publisher, which allows your app to know what actions to take based on the user's interaction. Simply add the following to your existing ViewModel layer to subscribe to the OwnID Event Publisher and respond to integration events (it can be placed just after the code that creates the OwnID view model instance).

[Complete example](../Demo/IntegrationDemo/RegisterViewModel.swift)
```swift
final class MyRegisterViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.RegisterView.ViewModel(registrationPerformer: CustomRegistration(),
                                                               loginPerformer: CustomLogin(),
                                                               loginIdPublisher: loginIdPublisher)

    init() {
     subscribe(to: ownIDViewModel.integrationEventPublisher)
    }

     func subscribe(to integrationEventPublisher: OwnID.RegistrationPublisher) {
       integrationEventPublisher
           .sink { [unowned self] event in
               switch event {
               case .success(let event):
                   switch event {
                    // Event when user successfully finishes OwnID registration flow
                   case .readyToRegister:
                     // Call register(:) function and 
                     // pass the custom user's parameters if needed

                     ownIDViewModel.register(registerParameters: parameters)

                   // Event when OwnID creates
                   // account in your system
                   // and logs in user
                   case .userRegisteredAndLoggedIn:
                     // User is registered and logged in with OwnID
                     
                   case .loading:
                     // Display loading indicator according to your designs

                   case .resetTapped:
                     // Event when user select "Undo" option in ready-to-register state
                   }

               case .failure(let error):
                // Handle OwnID.CoreSDK.Error here
               }
           }
           .store(in: &bag)
   }
}
```
> [!IMPORTANT]
>
> The OwnID `ownIDViewModel.register` function must be called in response to the `.readyToRegister` event. 

## Implement the Login Screen

The process of implementing your Login screen is very similar to the one used to implement the Registration screen. When the user selects Skip Password on the Login screen and if the user has previously set up OwnID authentication, allows them to log in with OwnID.

Like the Registration screen, you add Skip Password to your application's Login screen by including an OwnID view. In this case, it is `OwnID.LoginView`. This OwnID view has its own view model, `OwnID.LoginView.ViewModel`.

### Add OwnID View
Inserting the OwnID view into your View layer results in the Skip Password option appearing in your app. When the user selects Skip Password, the SDK opens a sheet to interact with the user. It is recommended that you place the OwnID view, `OwnID.LoginView`, immediately after the password text field. The code that creates this view accepts the OwnID view model as its argument. It is suggested that you pass user's email binding for properly creating accounts.

It is recommended to set height of button the same as text field and disable text field when OwnID is enabled.

[Complete example](../Demo/IntegrationDemo/LogInView.swift)
```swift
//Put LoginView inside your main view, preferably below password field
var body: some View {
  OwnID.FlowsSDK.LoginView(viewModel: ownIDViewModel)
  //...
}
```

![how it looks like](skip_button_design.png) ![how it looks like](skip_button_design_dark.png)

By default, tooltip popup will appear every time login view is shown.

For additional OwnIDButton UI customization see [Button Appearance](#button-appearance).

### Customize View Model
The OwnID view that inserts the Skip Password UI is bound to an instance of the OwnID view model. Before modifying your View layer, create an instance of this view model, `OwnID.FlowsSDK.RegisterView.ViewModel`, within your ViewModel layer with `CustomLogin` you created earlier:

[Complete example](../Demo/IntegrationDemo/LogInViewModel.swift)
```swift
final class MyLogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: CustomLoginPerformer(),
                                                            loginIdPublisher: loginIdPublisher)
}
```

 Where `loginIdPublisher` provides input that user is typing into loginID field. See example of `@Published` property in demo app.

After creating this OwnID view model, you should listen to integration events from the OwnID Event Publisher, which allows your app to know what actions to take based on the user's interaction with the Skip Password option. Simply add the following to subscribe to the OwnID Event Publisher and respond to integration events.

[Complete example](../Demo/IntegrationDemo/LogInViewModel.swift)
```swift
final class MyLogInViewModel: ObservableObject {
    // MARK: OwnID
    let ownIDViewModel = OwnID.FlowsSDK.LoginView.ViewModel(loginPerformer: CustomLoginPerformer(),
                                                            loginIdPublisher: loginIdPublisher)

 	  init() {
       subscribe(to: ownIDViewModel.integrationEventPublisher)
   	}

     func subscribe(to integrationEventPublisher: OwnID.LoginPublisher) {
       integrationEventPublisher
           .sink { [unowned self] event in
               switch event {
               case .success(let event):
                   switch event {
                   // Event when user who previously set up OwnID
                   // logs in with Skip Password
                   case .loggedIn:
                     // User is logged in with OwnID

                   case .loading:
                     // Display loading indicator according to your designs
                   }

               case .failure(let error):
                 // Handle OwnID.CoreSDK.Error here
               }
           }
           .store(in: &bag)
   }
}
```

## Tooltip

The OwnID SDK's `OwnIDButton` by default shows a Tooltip with text "Sign In with Fingerprint" / "Register with Fingerprint".

![OwnID Tooltip UI Example](tooltip_example.png) ![OwnID Tooltip Dark UI Example](tooltip_example_dark.png)

On Registration you can setup the logic of tooltip appearing. By default it appears if the `loginID` text input is valid. Here how you can customize it 

```swift
ownIDViewModel.shouldShowTooltipLogic = false
```

`OwnIDButton` view has parameters to specify tooltip background color, border color, text color, text size, shadowColor and tooltip position `top`/`bottom`/`leading`/`trailing` (default `bottom`). You can change them by setting values in view attributes:

```swift
OwnID.FlowsSDK.LoginView(viewModel: ownIDViewModel, visualConfig: OwnID.UISDK.VisualLookConfig(tooltipVisualLookConfig: OwnID.UISDK.TooltipVisualLookConfig(backgroundColor: .gray, borderColor: .black, textColor: .white, textSize: 20, tooltipPosition: .top)))
```

By default the tooltip has `zIndex(1)` to be above all other view. But if the OwnID View is inside some Stack and the tooltip is covered by another view it's recommended to set `zIndex(1)` for this stack

 ```swift
HStack {
    OwnID.FlowsSDK.LoginView(viewModel: ownIDViewModel)
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
- integrationError(underlying: Swift.Error) - General error for wrapping Integration errors OwnID integrates with.

## Alternative Syntax for Configure Function
If you followed the recommendation to add `OwnIDConfiguration.plist` to your project, calling `configure()` without any arguments is enough to initialize the SDK. If you did not follow this recommendation, you can still initialize the SDK with one of the following calls. Remember that these calls should be made within your app's `@main` `App` struct.

* `OwnID.CoreSDK.shared.configure(plistUrl: URL, userFacingSDK: SDKInformation, supportedLanguages: Languages)` explicitly provides the path to the OwnID configuration file, where `plist` is the path to the file.
* `OwnID.CoreSDK.shared.configure(appID: String, userFacingSDK: SDKInformation, supportedLanguages: Languages)` explicitly defines the configuration options rather than using a PLIST file. The app id is unique to your OwnID application, and can be obtained in the [OwnID Console](https://console.ownid.com). Additionally, you can use optional parameters and call `OwnID.CoreSDK.shared.configure(appID: config.OwnIDAppID, redirectionURL: config.OwnIDRedirectionURL, userFacingSDK: info, environment: config.OwnIDEnv, enableLogging: config.enableLogging, supportedLanguages: ["he"])`. For more information about `redirectionURL`, `environment`, `enableLogging` and `supportedLanguages` parameters, see [Advanced Configuration](sdk-advanced-configuration.md).

## Button Appearance
It is possible to set button visual settings by passing `OwnID.UISDK.VisualLookConfig`. Additionally, you can override default behaviour of tooltip appearing or other settings in `OwnID.UISDK.TooltipVisualLookConfig`.
By passing `widgetPosition`, `or` text view will change it's position accordingly. It is possible to modify look & behaviour of loader by modifying default settings of `loaderViewConfig` parameter.

```swift
let buttonViewConfig = OwnID.UISDK.ButtonViewConfig(iconColor: .red,
                                                    iconHeight: 30,
                                                    backgroundColor: .white,
                                                    borderColor: .red)
let orViewConfig = OwnID.UISDK.OrViewConfig(textSize: 20, textColor: .red)
let tooltipVisualLookConfig = OwnID.UISDK.TooltipVisualLookConfig(backgroundColor: .red,
                                                                  borderColor: .pink,
                                                                  textColor: .red, textSize: 30,
                                                                  shadowColor: .pink,
                                                                  tooltipPosition: .top)
let loaderViewConfig = OwnID.UISDK.LoaderViewConfig(color: .red, backgroundColor: .white)
let config = OwnID.UISDK.VisualLookConfig(buttonViewConfig: buttonViewConfig,
                                          orViewConfig: orViewConfig,
                                          tooltipVisualLookConfig: tooltipVisualLookConfig,
                                          widgetPosition: .trailing,
                                          loaderViewConfig: loaderViewConfig)

OwnID.FlowsSDK.LoginView(viewModel: ownIDViewModel, visualConfig: config)
```

if you want to change the `OwnIDButton` from side-by-side button to Password replacing button, use `widgetType = .authButton`

```swift
let buttonViewConfig = OwnID.UISDK.ButtonViewConfig(widgetType: .authButton)
let authButtonViewConfig = OwnID.UISDK.AuthButtonViewConfig(textSize: 20, 
                                                            height: 50,
                                                            textColor: .gray,
                                                            backgroundColor: .red)
let config = OwnID.UISDK.VisualLookConfig(authButtonConfig: authButtonViewConfig)

OwnID.FlowsSDK.LoginView(viewModel: ownIDViewModel, visualConfig: config)
```
