# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'Stratagem' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for Stratagem
  pod 'Firebase/Database'
  pod 'SwiftVideoBackground'
  pod 'SKTiled', :git => 'https://github.com/andrewpeng02/SKTiled.git', :commit => 'cd65692d521ecac1835c224b6a7e6ad52a5758d2'

  post_install do |installer|
      installer.pods_project.targets.each do |target|
          target.build_configurations.each do |config|
              config.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf'
              config.build_settings.delete 'IPHONEOS_DEPLOYMENT_TARGET'
              config.build_settings['ONLY_ACTIVE_ARCH'] = 'YES'
          end
      end
   end
end
