# Data Safety

OwnID SDK collects SDK event and log data to operate the service, measure reliability, and improve product quality. This log data does not include personal data that directly identifies the user, such as username, email, or password.

Log data may include general technical information such as IP address, device model, operating system version, event time, and SDK statistics. It is sent to OwnID using encrypted transport and is not shared with third-party services.

The SDK may keep lightweight local user state, such as the last used login identifier and authentication method, to keep SDK experiences consistent across app sessions.

Your app remains responsible for its own account data, session data, and consent.
