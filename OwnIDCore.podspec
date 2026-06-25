# OwnIDCore.podspec
Pod::Spec.new do |spec|
  spec.name             = "OwnIDCore"
  spec.version          = "4.0.0-rc1"
  spec.summary          = "OwnID iOS Core SDK"
  spec.description      = "OwnID Core for iOS helps mobile apps deliver modern, passkey-first authentication journeys. It provides the core runtime, APIs, and flow orchestration for login, verification, passkey registration and sign-in, enrollment, and web-based flows."
  spec.homepage         = "https://ownid.com"
  spec.license          = { :type => "Apache 2.0", :file => "LICENSE" }
  spec.authors          = "OwnID, Inc."

  spec.platform         = :ios, "13.0"
  spec.swift_versions   = ["6"]

  spec.source           = { :git => "https://github.com/OwnID/ownid-ios-sdk.git", :tag => spec.version.to_s }
  spec.module_name      = "OwnIDCore"

  # Sources & resources
  spec.source_files     = "OwnIDCore/Sources/**/*"
  spec.resource_bundles = { "OwnIDCore" => ["OwnIDCore/Resources/**/*"] }
end
