#!/bin/bash
# Fail closed if a renamed/filtered test or a newer simulator masks the sentinel.
set -euo pipefail
bundle="${1:?Pass the iOS 26.2 compatibility xcresult bundle}"
xcrun xcresulttool get test-results tests --path "$bundle" | ruby -rjson -e '
report = JSON.parse(STDIN.read)
devices = report.fetch("devices")
abort "Expected only iOS 26.2 simulators" unless !devices.empty? && devices.all? do |device|
  device["osVersion"] == "26.2" && device["platform"] == "iOS Simulator"
end
nodes = report.fetch("testNodes").dup
sentinels = []
until nodes.empty?
  node = nodes.shift
  nodes.concat(node.fetch("children", []))
  if node["nodeType"] == "Test Case" && node.fetch("nodeIdentifier", "").start_with?("IOS26DeinitCompatibilityTests/")
    sentinels << node
  end
end
abort "Missing compatibility tests (expected at least 11)" if sentinels.count < 11
abort "Compatibility tests failed or were skipped" unless sentinels.all? { |node| node["result"] == "Passed" }
puts "Verified #{sentinels.count} synchronous deinit sentinels passed on iOS 26.2."
'
