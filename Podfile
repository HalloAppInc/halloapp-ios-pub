platform :ios, '13.0'
use_frameworks!
workspace 'Halloapp.xcworkspace'

target 'Core' do
  project './Core/Core.xcodeproj'
  pod 'XMPPFramework/Swift', :git => 'git@github.com:HalloAppInc/XMPPFramework.git'
  pod 'Sodium', :git => 'git@github.com:HalloAppInc/swift-sodium.git'
end

target 'HalloApp' do
  pod 'XMPPFramework/Swift', :git => 'git@github.com:HalloAppInc/XMPPFramework.git'
  pod 'Firebase/Crashlytics'
  pod 'Sodium', :git => 'git@github.com:HalloAppInc/swift-sodium.git'
end

target 'HalloAppTests' do
  pod 'Firebase/Crashlytics'
end

target 'Notification Service Extension' do
  pod 'Firebase/Crashlytics'
end

target 'Share Extension' do
  pod 'Firebase/Crashlytics'
  pod 'XMPPFramework/Swift', :git => 'git@github.com:HalloAppInc/XMPPFramework.git'
end
