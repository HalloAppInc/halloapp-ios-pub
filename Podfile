platform :ios, '13.0'
use_frameworks!
workspace 'Halloapp.xcworkspace'

target 'Core' do
  project './Core/Core.xcodeproj'
  pod 'Sodium', :git => 'git@github.com:HalloAppInc/swift-sodium.git'
end

target 'HalloApp' do
  pod 'Sodium', :git => 'git@github.com:HalloAppInc/swift-sodium.git'
end

target 'HalloAppClip' do
  pod 'Sodium', :git => 'git@github.com:HalloAppInc/swift-sodium.git'
end

target 'HalloAppTests' do
end

target 'Notification Service Extension' do
end

target 'Share Extension' do
end

post_install do |pi|
    pi.pods_project.targets.each do |t|
      t.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '11.0'
      end
    end
end
