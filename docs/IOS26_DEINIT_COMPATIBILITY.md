# iOS 26.0–26.2 teardown compatibility

The affected Swift concurrency runtime can crash in `TaskLocal::StopLookupScope`
via `swift_task_deinitOnExecutorMainActorBackDeploy` when an isolated destructor
runs from a synchronous callback without a current Swift task. Passing tests on
a newer runtime, or changing a test to `async`, does not cover this path.

For independently constructed screen/account models, UIKit bridges, cache boxes
and their owned children, retain the explicit empty `nonisolated deinit {}`.
Main-actor isolation of their state and methods is unchanged. Existing explicit
destructors (task cancellation, observers, etc.) are left intact. Do not move
actor-isolated cleanup into these empty destructors or disable default actor
isolation for the module.

`IOS26DeinitCompatibilityTests` intentionally uses **synchronous XCTest**. It
asserts there is no current Task, binds a task-local value, drops the last strong
reference inside that scope and checks weak references after autorelease pools
drain. It exercises page dismissal, timeline pruning, nested notification models,
scroll-wrapper replacement, UIKit containment and cache churn.

Run on an installed **iOS 26.2** simulator (replace the destination UUID):

```sh
xcodebuild -project moro.xcodeproj -scheme moro -testPlan Moro-UnitTests \
  -destination 'platform=iOS Simulator,id=IOS_26_2_SIMULATOR_UUID' \
  -only-testing:moroTests/IOS26DeinitCompatibilityTests \
  -only-testing:moroTests/RootTabCoordinatorTests test
```

Also build Release and inspect private as well as public deallocation symbols:

```sh
xcodebuild -project moro.xcodeproj -scheme moro -configuration Release \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/moro-compat build
bash scripts/check-isolated-deinits.sh \
  /tmp/moro-compat/Build/Products/Release-iphonesimulator/moro.app/moro
```

The symbol gate covers private classes inaccessible to unit tests. Only the
enumerated private-init, process-lifetime singletons, the application delegate,
and generated SwiftPM resource markers are exempt. A singleton cache does **not**
make its evictable entries process-lifetime. If an exempt type becomes transient,
remove the exemption and cover its release.

CI has a separate pinned iOS 26.2 lane; missing runtime installation is an error,
never a fallback to the newest OS. It runs the compatibility and navigation
sentinels plus timeline, notification, compose and profile regression suites,
and checks the Release executable. Keep newer-runtime and minimum-OS checks when
upgrading the compiler. This guards a specific runtime failure, not all possible
future OS crashes.
