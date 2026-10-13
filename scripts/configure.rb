require 'xcodeproj'
require 'json'
# Resolve each direct Swift package at its historical revision.
project_path = 'AltStore.xcodeproj/project.pbxproj'
source = File.read(project_path)
JSON.parse(File.read('AltStore.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'))['pins'].each do |pin|
  url = Regexp.escape(pin['location'])
  revision = pin['state']['revision']
  source.gsub!(/(repositoryURL = "?#{url}"?;\s*requirement = )\{[^}]+\};/) do
    "#{$1}{ kind = revision; revision = #{revision}; };"
  end
end
File.write(project_path, source)
project = Xcodeproj::Project.open('AltStore.xcodeproj')
app = project.targets.find { |t| t.uuid == 'BFD247692284B9A500981D42' }
raise 'Missing app target' unless app
# iOS 14 widget cannot be embedded in an iOS 12 app.
project.targets.select { |t| t.name.include?('Widget') }.each do |widget|
  project.targets.each do |t|
    t.dependencies.select { |d| d.target == widget }.each(&:remove_from_project)
    t.copy_files_build_phases.each { |p| p.files.select { |f| f.file_ref == widget.product_reference }.each(&:remove_from_project) }
  end
  widget.remove_from_project
end
project.build_configurations.each { |c| c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0' }
project.targets.each do |t|
  t.build_configurations.each do |c|
    c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0' if t.platform_name == :ios
    c.build_settings['ENABLE_BITCODE'] = 'NO'
    c.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    c.build_settings['SWIFT_VERSION'] = '5.0' if c.build_settings['SWIFT_VERSION']
  end
  # SDK frameworks introduced after iOS 12 must be weak linked.
  t.frameworks_build_phase.files.each do |f|
    if f.file_ref && %w[Combine.framework SwiftUI.framework WidgetKit.framework UniformTypeIdentifiers.framework].include?(f.file_ref.path.to_s.split('/').last)
      f.settings = { 'ATTRIBUTES' => ['Weak'] }
    end
  end
end
kit = project.main_group.find_subpath('AltPocketKit', true)
kit.set_source_tree('SOURCE_ROOT')
kit.set_path('AltPocketKit')
Dir['AltPocketKit/*.swift'].sort.each do |file|
  ref = kit.files.find { |f| f.path == File.basename(file) } || kit.new_file(File.basename(file))
  app.source_build_phase.add_file_reference(ref, true)
end
app.add_system_framework('NetworkExtension')
app.add_system_framework('Network')
unless project.targets.any? { |t| t.name == 'LocalTunnel' }
  tunnel = project.new_target(:app_extension, 'LocalTunnel', :ios, '12.0')
  group = project.main_group.new_group('LocalTunnel', 'LocalTunnel', 'SOURCE_ROOT')
  tunnel.add_file_references([group.new_file('PacketTunnelProvider.swift')])
  tunnel.add_system_framework('NetworkExtension')
  tunnel.build_configurations.each do |c|
    c.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => 'io.altpocket.AltPocket.LocalTunnel',
      'PRODUCT_NAME' => 'LocalTunnel',
      'SWIFT_VERSION' => '5.0', 'SKIP_INSTALL' => 'YES',
      'INFOPLIST_FILE' => 'LocalTunnel/Info.plist',
      'CODE_SIGN_ENTITLEMENTS' => 'LocalTunnel/LocalTunnel.entitlements',
      'CODE_SIGNING_ALLOWED' => 'NO', 'APPLICATION_EXTENSION_API_ONLY' => 'YES',
      'TARGETED_DEVICE_FAMILY' => '1,2', 'ENABLE_BITCODE' => 'NO',
      'LD_RUNPATH_SEARCH_PATHS' => ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
    })
  end
  app.add_dependency(tunnel)
  phase = app.new_copy_files_build_phase('Embed LocalTunnel')
  phase.dst_subfolder_spec = '13'
  build_file = phase.add_file_reference(tunnel.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
app.build_configurations.each do |c|
  c.build_settings['PRODUCT_NAME'] = 'AltPocket'
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'io.altpocket.AltPocket'
  c.build_settings['ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES'] = 'YES'
end
project.save
puts 'Configured AltPocket and embedded LocalTunnel for iOS 12.0'

# num_threads 0.1.7 calls a libc Rust wrapper removed in newer libc.
# Preserve its behavior using Darwin's exported task-port symbol.
%w[em_proxy minimuxer].each do |name|
  path = "Dependencies/#{name}/Cargo.toml"
  text = File.read(path)
  unless text.include?('[patch.crates-io]')
    File.write(path, text + "\n[patch.crates-io]\nnum_threads = { path = \"../../Vendor/num_threads-0.1.7\" }\n")
  end
end
