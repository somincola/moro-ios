#!/bin/bash
# Inspect the unstripped Release simulator binary, including private symbols.
# Usage: bash scripts/check-isolated-deinits.sh path/to/moro.app/moro
set -euo pipefail

binary="${1:?Pass the unstripped Release simulator executable}"
if [[ ! -f "$binary" ]]; then
  echo "Missing executable: $binary" >&2
  exit 1
fi

xcrun nm -arch arm64 -j "$binary" | xcrun swift-demangle | ruby -e '
symbols = STDIN.each_line.map do |line|
  line.strip.sub(/^merged /, "").gsub(/\((\w+) in _[A-Fa-f0-9]+\)/, "\\1")
end.select { |line| line.start_with?("moro.") }.uniq
abort "No Moro deinit symbols found; use an unstripped Release simulator binary" unless
  symbols.any? { |line| line.end_with?(".__deallocating_deinit") }

# These private-init singletons are retained for the entire process. Their
# independently evictable children are NOT exempt. Revisit if ownership changes.
process_lifetime = %w[
  AppSettings CacheManager EmojiService NetworkLogger NetworkMonitor
  StartupPerformanceTracker StatusDataControllerProvider
  StatusDetailPerformanceTracker StatusDetailPrefetchCoordinator
  StreamWatcher TimelineDetectionManager UserInteractionService
  PushSubscriptionCoordinator
].map { |name| "moro.#{name}" }
# UIKit owns the one application delegate. SwiftPM generates resource markers;
# the app does not instantiate those marker classes.
allowed = process_lifetime + %w[moro.MoroAppDelegate moro.ResourceBundleClass]
isolated = symbols.grep(/\.__isolated_deallocating_deinit$/)
  .map { |line| line.delete_suffix(".__isolated_deallocating_deinit") }.sort
unexpected = isolated - allowed
unless unexpected.empty?
  warn "Unexpected isolated destructors (unsafe on iOS 26.0–26.2):"
  unexpected.each { |name| warn "  #{name}" }
  abort "Review the lifetime and add a nonisolated deinit; do not widen the allowlist for transient objects."
end
puts "Isolated-deinit audit passed (#{isolated.count} process-lifetime / generated types remain)."
'
