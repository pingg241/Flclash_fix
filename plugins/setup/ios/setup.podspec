Pod::Spec.new do |s|
  s.name             = 'setup'
  s.version          = '0.0.1'
  s.summary          = 'FlClash Go core build harness'
  s.description      = <<-DESC
FlClash Go core build harness (FFI plugin).
                       DESC
  s.homepage         = 'https://github.com/chen08209/FlClash'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'FlClash' => 'chen08209@gmail.com' }
  s.module_name      = 'setup'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
