#
# patchfly.podspec
#
# CocoaPods spec for the Patchfly iOS plugin.
# This is the equivalent of sdk/android/build.gradle for Android.
#
# To integrate in your Flutter app's ios/Podfile:
#   The Flutter tooling auto-generates this from pubspec.yaml's ios.pluginClass.
#

Pod::Spec.new do |s|
  s.name             = 'patchfly'
  s.version          = '0.1.0'
  s.summary          = 'Patchfly SDK — OTA updates for Flutter apps (iOS)'
  s.description      = <<-DESC
Patchfly enables over-the-air updates for Flutter apps. On iOS, it patches
the Flutter engine's AOT snapshot (App.framework/App) using bsdiff patches
downloaded from the Patchfly server.
                       DESC
  s.homepage         = 'https://patchfly.dev'
  s.license          = { :type => 'MIT', :file => '../../LICENSE-MIT' }
  s.author           = { 'Patchfly' => 'dev@patchfly.dev' }
  s.source           = { :git => 'https://github.com/fatmuh/patchfly.git', :tag => s.version.to_s }

  s.source_files = 'Classes/**/*.{swift,h}'
  s.public_header_files = 'Classes/**/*.h'

  s.swift_version = '5.0'
  s.platform = :ios, '12.0'

  s.dependency 'Flutter'

  # The Rust static library (libpatchfly_updater.a) must be added
  # to the app's Xcode project separately. See docs/IOS_INTEGRATION.md.
  # s.vendored_libraries = 'libpatchfly_updater.a'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
