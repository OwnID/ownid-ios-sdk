Pod::Spec.new do |s|
  s.name             = 'ownid-core-ios-sdk'
  s.version          = '2.2.5'
  s.summary          = 'ownid-core-ios-sdk'

  s.description      = <<-DESC
  ownid-core-ios-sdk
                       DESC

  s.homepage         = 'https://ownid.com'
  s.license          = 'Apache 2.0'
  s.authors          = 'OwnID, Inc'

  s.source           = { :git => 'https://github.com/OwnID/ownid-ios-sdk-demo.git', :tag => s.version.to_s }
  s.module_name   = 'OwnIDCoreSDK'
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.1.1'

  s.source_files = 'ownid-core-ios-sdk/Core/**/*', 'ownid-core-ios-sdk/Flows/**/*', 'ownid-core-ios-sdk/UI/**/*'
  s.resource_bundles = { 'OwnIDCoreSDK' => ['ownid-core-ios-sdk/Resources/**/*'] }
end
