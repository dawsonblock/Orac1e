#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

project_root = File.expand_path("..", __dir__)
project_path = File.join(project_root, "OracleController.xcodeproj")
version = File.read(File.join(project_root, "Sources/OracleOS/Common/Types.swift"))[/version = "([^"]+)"/, 1] || "1.0.0"

FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)
project.root_object.attributes["LastUpgradeCheck"] = "2600"
project.root_object.attributes["ORGANIZATIONNAME"] = "Oracle OS"

app_target = project.new_target(:application, "Oracle Controller", :osx, "14.0")
dmg_target = project.new_aggregate_target("Oracle Controller DMG", [], :osx, "14.0")

[app_target, dmg_target].each do |target|
  target.build_configurations.each do |config|
    config.build_settings["PRODUCT_NAME"] = target.name
    config.build_settings["CURRENT_PROJECT_VERSION"] = version
    config.build_settings["MARKETING_VERSION"] = version
  end
end

app_target.build_configurations.each do |config|
  config.build_settings["INFOPLIST_FILE"] = "AppResources/OracleController/Info.plist"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.oracleos.controller"
  config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "AppResources/OracleController/OracleController.entitlements"
  config.build_settings["ENABLE_HARDENED_RUNTIME"] = "YES"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  config.build_settings["SDKROOT"] = "macosx"
  config.build_settings["SUPPORTED_PLATFORMS"] = "macosx"
  config.build_settings["WRAPPER_EXTENSION"] = "app"
end

app_phase = app_target.new_shell_script_build_phase("Build Oracle Controller App Bundle")
app_phase.shell_script = <<~SCRIPT
  set -euo pipefail
  CONFIGURATION_LOWER="$(printf '%s' "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"
  "${SRCROOT}/scripts/build-controller-app.sh" --configuration "${CONFIGURATION_LOWER}" --output-dir "${SRCROOT}/dist" --build-number "${CURRENT_PROJECT_VERSION}"
  rm -rf "${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
  cp -R "${SRCROOT}/dist/Oracle Controller.app" "${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
SCRIPT

dmg_target.add_dependency(app_target)
dmg_phase = dmg_target.new_shell_script_build_phase("Create Oracle Controller DMG")
dmg_phase.shell_script = <<~SCRIPT
  set -euo pipefail
  CONFIGURATION_LOWER="$(printf '%s' "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"
  "${SRCROOT}/scripts/create-controller-dmg.sh" --configuration "${CONFIGURATION_LOWER}" --output-dir "${SRCROOT}/dist" --build-number "${CURRENT_PROJECT_VERSION}"
SCRIPT
dmg_phase.output_paths = ["${SRCROOT}/dist/Oracle-Controller-#{version}.dmg"]

project.save

workspace_path = File.join(project_root, "OracleController.xcworkspace", "contents.xcworkspacedata")
workspace = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Workspace
     version = "1.0">
     <FileRef
        location = "group:Package.swift">
     </FileRef>
     <FileRef
        location = "group:OracleController.xcodeproj">
     </FileRef>
  </Workspace>
XML

File.write(workspace_path, workspace)
