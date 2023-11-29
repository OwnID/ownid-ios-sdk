# OwnID Redirect iOS

The OwnID Redirect iOS SDK help iOS app that use WebView or Safari to redirect back from browser to native app.

## Create URL Type (Custom URL Scheme)
The redirection URL determines where the user lands once they are done using their browser to interact with the OwnID web app. This ensures that the screen set view is closed after the user is logged in or registered. The custom scheme of this redirection URL must be defined in two places:
- In the [OwnID Console](http://console.ownid.com), where the custom scheme is the value of the Redirection URL field of your OwnID application.
- In Xcode, where you navigate to **Info > URL Types**, and then use the **URL Schemes** field to specify the redirection URL scheme.

For example, if your redirection URL scheme is `com.myapp.demo://myhost`, then you must specify this scheme in both places.
