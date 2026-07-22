# MgRead 打包与公共发布

本文是 `lingy-Mg/Mg-Read` 公共构建的可复现操作手册。工作流、构建参数或产物目录变化时，必须在同一次修改中更新本文。

## 公共 CI 打包

公共仓库的 `.github/workflows/public-build.yml` 会检出私库指定提交，并并行构建 Windows、Android、Linux x64、Linux arm64、macOS、Harmony。完整补发命令：

```powershell
gh workflow run public-build.yml `
  --repo lingy-Mg/Mg-Read `
  -f source_repository=lingy-Mg/Legado-Tauri `
  -f source_ref=main `
  -f source_sha=<完整提交SHA> `
  -f targets=all `
  -f release_tag=<v版本标签> `
  -f release_version=<完整构建版本>
```

## 构建性能与缓存边界

- Android 线上只构建 arm64、armv7、x86_64 三个独立 matrix job，并发编译后由发布任务合并产物；32 位 x86 已停止发布，禁止重新加入 matrix，也禁止塞回单个 `android all` job 串行构建。
- Harmony 线上把 `Tauri OHOS release` 与 `ArkTS release` 作为两个正式 matrix 变体并发构建，再由轻量汇总 job 合并。Tauri OHOS 已是发布门禁，禁止删除、跳过、改回测试 HAP，或与 ArkTS 塞回同一 job 串行执行。
- Rust 构建统一使用有容量上限的平台/ABI 独立本地 `sccache` 目录，并由 `actions/cache` 整包保存；Android 每 ABI 上限 512 MB，桌面、Linux 和 Harmony 每平台上限 1 GB。禁止启用 `SCCACHE_GHA_ENABLED`：逐对象后端在全平台并发构建时会产生数千次 Cache API 写入并触发限流。禁止恢复各平台完整 `target` 目录；这类缓存单份可达数 GB，会挤占仓库缓存额度，而且依赖键变化后仍会重新编译 workspace crate。
- HarmonyOS SDK 按下载包 SHA-256 缓存，正式 Tauri OHOS CLI 按锁文件对应的提交与 `ohrs` 版本缓存。缓存命中时不得再次下载 SDK 或执行 `cargo install`。
- pnpm、Gradle、OHPM/Hvigor 继续使用各自依赖锁文件作为缓存键；发布版本号或 `build-profile.json5` 变化不得使 Harmony 依赖缓存失效。
- 线上提速验收必须同时查看 job 耗时和日志中的 sccache 统计、SDK/CLI 复用提示，不能只凭工作流里存在 `cache` 字样判断已经生效。

也可以从私库根目录触发：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trigger-public-build.ps1 `
  -PublicRepo lingy-Mg/Mg-Read `
  -Target all
```

公共仓库必须配置 `PRIVATE_SOURCE_REPOSITORY`、`PRIVATE_SOURCE_PAT`、Android 签名四项 Secret、`RELEASE_ARCHIVE_PASSWORD`；Harmony 正式 HAP 使用私库提交中现有的 release 签名材料。QQ Bot 三项 Secret 只影响通知，不影响打包。

## 本地构建入口

所有命令均从私库根目录执行，首次构建先安装锁定依赖：

```powershell
corepack pnpm@11.12.0 install --frozen-lockfile
```

| 平台 | 命令 | 运行环境 |
| --- | --- | --- |
| Windows | `corepack pnpm@11.12.0 build -- windows release` | Windows x64、MSVC |
| Android 线上 ABI | `corepack pnpm@11.12.0 build -- android <arm64|armv7|x86_64> release` | Android SDK/NDK、JDK 21，三个 ABI 独立并发 job |
| Linux x64 | `corepack pnpm@11.12.0 build -- linux x64 release` | Linux x64 与 Tauri WebKit 依赖 |
| Linux arm64 | `corepack pnpm@11.12.0 build -- linux arm64 release` | Linux arm64 原生 runner |
| macOS universal | `corepack pnpm@11.12.0 build -- macos release` | macOS、Apple x64/arm64 Rust targets |
| Harmony Tauri OHOS release | `cargo-tauri ohos build --ci --target aarch64 x86_64` | 正式 signed HAP；外层先编译 arm64 release，Hvigor hook 只补 x86_64 release |
| Harmony ArkTS release | `ohpm install --all` + `hvigorw assembleHap --mode module -p product=default -p buildMode=release` | 正式 signed HAP；Hvigor hook 自动同步 Web 资源 |

桌面、Android 和 macOS 归一化产物写入私库根目录的 `构建结果/`。Linux 公共 CI 额外从 `apps/mg-read/src-tauri/target/<target>/release/mg-read` 创建 `.tar.gz`。Harmony 公共 CI 必须同时产出 `MgRead-harmony-tauri-ohos-*` 与 `MgRead-harmony-arkts-*` 两个正式 signed HAP；任一变体失败或缺失都必须让 `Collect Harmony releases` 失败，不能发布残缺的 Harmony 压缩包。

## 模板上线同步

私库模板不会自动更新公共仓库。至少同步这些文件：

- `.github/workflows/public-build.yml`
- `PACKAGING.md`
- `scripts/prepare-public-build-artifacts.mjs`
- `scripts/create-protected-archives.ps1`
- `scripts/send-qq-message.py`

同步后比较 Git blob SHA；两边必须相同：

```powershell
git hash-object .\scripts\public-build-repo-template\.github\workflows\public-build.yml
gh api repos/lingy-Mg/Mg-Read/contents/.github/workflows/public-build.yml --jq .sha
```

## 六平台验收

一次完整构建只有同时满足以下条件才算成功：

1. `Resolve Context` 成功，`source_sha` 等于请求的完整 SHA。
2. Windows、Android、Linux x64、Linux arm64、macOS、Harmony 六个 build job 都是 `success`。
3. 六个最终 `package-*` Actions artifact 都存在且非空。
4. Harmony 的 Tauri OHOS 与 ArkTS matrix 变体均成功，最终 `package-harmony` 同时包含两个正式 signed HAP；Tauri OHOS 不是测试产物，禁止缺省。
5. `Publish Release` 成功，Release 同时包含六个平台压缩包和 `build-manifest.json`。
6. `build-manifest.json` 中六个平台结果全为 `success`；Release 成功但任一平台失败仍应判定为“部分成功”。
