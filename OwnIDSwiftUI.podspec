# OwnIDSwiftUI.podspec
Pod::Spec.new do |spec|
  spec.name             = "OwnIDSwiftUI"
  spec.version          = "4.0.0-rc1"
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
