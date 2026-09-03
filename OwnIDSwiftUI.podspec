# OwnIDSwiftUI.podspec
sdk_version_file = File.join(__dir__, "sdk-version.xcconfig")
sdk_version = File.read(sdk_version_file)[/^\s*SDK_VERSION\s*=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$/, 1]
raise "SDK_VERSION is missing or invalid in #{sdk_version_file}" unless sdk_version

Pod::Spec.new do |spec|
  spec.name             = "OwnIDSwiftUI"
  spec.version          = sdk_version
  spec.summary          = "OwnID iOS SwiftUI SDK"
  spec.description      = "OwnID SwiftUI provides polished SwiftUI components for integrating OwnID user journeys. It includes UI for login ID collection and verification, plus reusable login and create-passkey widgets that work with OwnID Core."
  spec.homepage         = "https://ownid.com"
  spec.license          = { :type => "Apache 2.0", :file => "LICENSE" }
  spec.authors          = "OwnID, Inc."

  spec.platform         = :ios, "13.0"
  spec.swift_versions   = ["6"]

  spec.source           = { :git => "https://github.com/OwnID/ownid-ios-sdk.git", :tag => spec.version.to_s }
  spec.module_name      = "OwnIDSwiftUI"

  # Sources
  spec.source_files     = "OwnIDSwiftUI/Sources/**/*"

  spec.dependency       "OwnIDCore", spec.version.to_s

end
