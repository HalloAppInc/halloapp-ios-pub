platform :ios, '13.0'
use_frameworks!
workspace 'Halloapp.xcworkspace'

target 'Core' do
  project './Core/Core.xcodeproj'
  pod 'XMPPFramework/Swift', :git => 'git@github.com:HalloAppInc/XMPPFramework.git'
  pod 'Firebase/Crashlytics'
end

target 'HalloApp' do
  pod 'Firebase/Crashlytics'
  pod 'NextLevelSessionExporter', '>= 0.4.5'
  pod 'XMPPFramework/Swift', :git => 'git@github.com:HalloAppInc/XMPPFramework.git'
  pod 'YPImagePicker', :git => 'git@github.com:HalloAppInc/YPImagePicker.git', :tag => '4.2.6'
end

target 'Notification Service Extension' do
  pod 'Firebase/Crashlytics'
end
