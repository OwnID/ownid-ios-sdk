platform :ios, '16.0'
use_frameworks!

def core_pods
  pod 'ownid-core-ios-sdk', :path => '../ownid-core-ios-sdk/'
end

def gigya_pods
  pod 'Gigya'
  pod 'ownid-gigya-ios-sdk', :path => '../ownid-gigya-ios-sdk/'
  core_pods
end

target 'ScreensetsDemo' do
  gigya_pods
end

target 'UIKitInjectionDemo' do
  gigya_pods
end

target 'GigyaDemo' do
  gigya_pods
end

target 'FirebaseDemo' do
  core_pods
  pod 'ownid-firebase-ios-sdk', :path => '../ownid-firebase-ios-sdk/'
end
