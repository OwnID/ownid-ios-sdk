Pod::Spec.new do |s|
  s.name             = 'ownid-gigya-ios-sdk'
  s.version          = '2.2.0'
  s.summary          = 'ownid-gigya-ios-sdk'

  s.description      = <<-DESC
  ownid-gigya-ios-sdk
                       DESC

  s.homepage         = 'https://ownid.com'
  s.license          = 'Apache 2.0'
  s.authors          = 'OwnID, Inc'

  s.source           = { :git => 'https://github.com/OwnID/ownid-gigya-ios-sdk.git', :tag => s.version.to_s }
  s.module_name   = 'OwnIDGigyaSDK'
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.1.1'

  s.source_files = 'Core/**/*'
  s.dependency 'ownid-core-ios-sdk', '2.2.0'
  s.dependency 'Gigya'
end
