# Xcode Cloud 工作流

## 工作流约定

| 设置 | Moro - CI | Moro - Release |
| --- | --- | --- |
| 用途 | 编译并运行单元测试，不分发 | 运行单元测试并生成可用于 TestFlight / App Store 的归档 |
| 自动触发 | `main` 提交、目标为 `main` 的 PR 更新 | 无 |
| 手动触发 | 任意分支 | `main`、前缀为 `codex/release-` 的发布分支 |
| 测试 | `Moro-UnitTests`，Required to Pass | `Moro-UnitTests`，Required to Pass |
| 归档 | 无 | `moro` Scheme，Release 配置，App Store Connect |
| Clean | 关闭 | 开启 |
| 自动取消旧构建 | 对同一分支 / PR 开启 | 不配置自动触发或自动取消 |
| Post-Actions | 无分发操作 | 不新增自动外部分发或 App Store 送审 |

首次启用 CI 时，先保持仅手动触发；同一配置在 Cloud 验证通过后，再启用 `main` 和 PR 的自动触发。
修改工作流不会重新提交或替换已经送审的构建。

## 共享环境

- `Moro Stable Xcode`：固定为 Xcode 26.6（17F113）。
- `Moro Stable macOS`：固定为 macOS Tahoe 26.6.2（25G83）。
- 单元测试使用该环境提供的 iPhone 17 Pro / iOS 26.5 模拟器。

在 App Store Connect → Xcode Cloud → Settings → Custom Aliases 中管理别名。
新版本应先验证，再统一升级别名；不要切换到自动跟随 Beta 的环境。
自定义别名目前可能在公开 API 的 `xcodeVersion` / `macOsVersion` 关系中返回 `null`；
核验时同时检查网页中的别名和实际构建日志，不要因此覆盖为 Latest Release。

## 测试计划

- `Moro-AllTests.xctestplan`：包含 `moroTests`、`moroUITests`，保持 `moro` Scheme 的本地默认全量测试行为。
- `Moro-UnitTests.xctestplan`：仅包含 `moroTests`，供两条 Cloud 工作流显式选择。
- 两条计划均纳入版本控制；Cloud 只能读取已经推送到所选分支的配置。

`AppStoreMetadataTests` 需要读取原始商店文案、本地化目录与少量工程源码。
测试 target 的 `Prepare App Store Test Fixtures` 构建阶段会从当前 checkout
按白名单打包这些原始文本到 `moroTests.xctest/RepositoryFixtures.plist`，测试统一从 bundle 读取。
这适配 Cloud 的 `build-for-testing` / `test-without-building` 分离执行，
不跳过断言，也不会把测试资料加入上架 App。脚本沙箱保持开启；文件和文案目录显式声明为只读输入，
测试 target 开启递归目录输入，唯一输出限制为测试 bundle 内的快照文件。

本地检查计划：

```sh
xcodebuild -project moro.xcodeproj -scheme moro -showTestPlans
```

本地单元测试：

```sh
xcodebuild -project moro.xcodeproj -scheme moro \
  -testPlan Moro-UnitTests \
  -destination 'platform=iOS Simulator,name=<已安装的 iPhone 模拟器>' test
```

## 手动触发与编号

```sh
asc xcode-cloud run --app 6776115614 --workflow "Moro - CI" --branch main
asc xcode-cloud run --app 6776115614 --workflow "Moro - Release" --branch main
```

这两个命令触发的是云端构建；`asc xcode archive` 则调用本机 Xcode。
Cloud 的构建流水号与本地 `CURRENT_PROJECT_VERSION` 不会自动互相回写。
即使只是运行 CI、不上传安装包，也应以 Cloud 实际显示的下一编号为准；
本地上传前还需核对 App Store Connect 的已处理构建和正在上传的构建：

```sh
asc builds next-build-number --app 6776115614 --version <目标版本> --platform IOS
```

不要同时从本地和 Cloud 上传相同版本、相同构建号的两个不同二进制文件。
TestFlight 测试组的既有访问策略与工作流 Post-Actions 是独立配置；本次不修改测试组权限。
后续需要停用工作流时优先 Deactivate，避免删除历史构建和产物。
