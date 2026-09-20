# CI 与发布工作流

## 工作流约定

日常测试由 GitHub Actions 负责，Xcode Cloud 仅用于手动创建发布候选包。
测试不会上传安装包，也不会修改工程版本号或推进 Xcode Cloud 构建编号。

| 设置 | GitHub Actions：CI | Xcode Cloud：Moro - Release |
| --- | --- | --- |
| 用途 | 编译并运行单元测试，不分发 | 运行单元测试并生成可用于 TestFlight / App Store 的归档 |
| 自动触发 | `dev` / `main` 提交、PR 更新 | 无 |
| 手动触发 | `workflow_dispatch`，选择分支 | `main`、前缀为 `codex/release-` 的发布分支 |
| 测试 | 显式选择 `Moro-UnitTests`，失败则 CI 失败 | `Moro-UnitTests`，Required to Pass |
| 归档 | 无 | `moro` Scheme，Release 配置，App Store Connect |
| Clean | 每次使用 GitHub 托管 runner | 开启 |
| 自动取消旧构建 | 同一 Git ref 的新运行取消旧运行 | 不配置自动触发或自动取消 |
| 分发与送审 | 无 | 无 Post-Actions；送审保持手动 |

原 Cloud 工作流 `Moro - CI` 已停用，保留历史构建和产物，不删除。
其原有分支 / PR 触发条件保留为历史配置；重新启用会恢复自动触发，
与 GitHub 重复运行单元测试，并重新推进 Cloud 编号。
修改工作流不会重新提交或替换已经送审的构建。

## 构建环境

GitHub Actions 的配置位于 `.github/workflows/ci.yml`：

- runner 固定为 `macos-26`，Xcode 固定为 `26.6`。
- 从 Xcode 支持的 iPhone 模拟器中选择最新已安装 iOS runtime。
- 保留模拟器 ad-hoc 签名，确保涉及 Keychain entitlement 的测试可运行。

Xcode Cloud 的 Release 工作流固定为 API 列出的兼容组合：

- Xcode 26.6（17F113）。
- macOS Tahoe 26.5.1（25F80）。
- 单元测试使用该环境提供的 iPhone 17 Pro / iOS 26.5 模拟器。

此前工作流使用 `Moro Stable Xcode` 和 `Moro Stable macOS` 自定义别名。
2026-09-20，Cloud 报告两者的组合不可用，构建 28 在分配构建机前失败；
因此改为上述明确版本。别名仍保留在 Settings → Custom Aliases，但 Release 工作流不再引用。
升级工具链时先核验 Xcode 与 macOS 的兼容组合，再同步更新 GitHub 的 Xcode 固定版本和 Cloud；
GitHub runner 标签只固定 macOS 大版本，镜像仍会更新；不要自动跟随 Xcode Beta。

## 测试计划

- `Moro-AllTests.xctestplan`：包含 `moroTests`、`moroUITests`，保持 `moro` Scheme 的本地默认全量测试行为。
- `Moro-UnitTests.xctestplan`：仅包含 `moroTests`，由 GitHub CI 和 Cloud Release 显式选择。
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

仅运行日常测试：

```sh
gh workflow run ci.yml --repo somincola/moro-ios --ref main
```

准备发布候选包时，手动运行 Cloud Release：

```sh
asc xcode-cloud run --app 6776115614 --workflow "Moro - Release" --branch main
```

`asc xcode archive` 调用本机 Xcode，不是 Xcode Cloud。

- 对外版本号由 `MARKETING_VERSION` 管理，在准备新版本时更新；CI 不自动递增。
- 同一产品的所有 Cloud 工作流共用一个递增构建编号序列，拆分工作流不会拆分编号。
- GitHub 单元测试不创建 Cloud build run，不消耗 Cloud 编号。
- 通过 Cloud 上传的安装包使用对应 Cloud 构建号；Cloud 编号与工程中的
  `CURRENT_PROJECT_VERSION` 不会自动互相回写，不需要为每次 Cloud 打包提交构建号修改。
- 发布构建失败、取消或重跑仍可能占号，成功上传的安装包不保证连续编号。
- 停用 Cloud CI 不会回退已有编号；下一次 Release 以 Cloud Settings → Build Number 为准。

本地上传前还需核对 App Store Connect 的已处理构建和正在上传的构建：

```sh
asc builds next-build-number --app 6776115614 --version <目标版本> --platform IOS
```

不要同时从本地和 Cloud 上传相同版本、相同构建号的两个不同二进制文件。
TestFlight 测试组的既有访问策略与工作流 Post-Actions 是独立配置。
后续需要停用工作流时优先 Deactivate，避免删除历史构建和产物。
