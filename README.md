# Public Build Repo Template

这个模板用于新建一个公开仓库，让公开仓库通过 GitHub Actions 拉取当前私有 `Legado-Tauri` 指定 commit，再免费构建并发布 Windows / Android 压缩包。

## 目录用途

- `.github/workflows/public-build.yml`
  - 公开仓库的 GitHub Actions 工作流。
- `scripts/create-protected-archives.ps1`
  - 把 `.exe` / `.apk` 打成带密码的压缩包，再上传到公开仓库 Release。

## 建议仓库初始化步骤

1. 新建一个公开仓库，例如 `lingy-Mg/Mg-Read`。
2. 把本模板完整复制到公开仓库根目录。
3. 在公开仓库 `Settings -> Secrets and variables -> Actions` 中添加以下 Secrets：

- `PRIVATE_SOURCE_REPOSITORY`
  - 私库仓库名，例如 `lingy-Mg/Legado-Tauri`。
- `PRIVATE_SOURCE_PAT`
  - 具备私库只读权限的 GitHub PAT，至少要能 checkout 私库源码。
- `ANDROID_KEYSTORE_BASE64`
  - Android release keystore 的 Base64 内容。
- `ANDROID_KEY_ALIAS`
  - Android release 签名 alias。
- `ANDROID_KEYSTORE_PASSWORD`
  - Android keystore 密码。
- `ANDROID_KEY_PASSWORD`
  - Android key 密码。
- `RELEASE_ARCHIVE_PASSWORD`
  - 对外发布压缩包时使用的密码。

## 触发方式

主路径应该是私库 GitHub Actions 自动触发：

- 私库新增 `Dispatch Public Build` workflow。
- 每次 `main` 分支 push 后，私库自动向公开仓库发送 `repository_dispatch`。
- 私库需配置：
  - Actions Secret: `PUBLIC_BUILD_REPO_PAT`
  - Actions Variable: `PUBLIC_BUILD_REPO=lingy-Mg/Mg-Read`
  - Actions Variable: `PUBLIC_BUILD_TARGETS=windows,android`

手动脚本仅保留给补发或排障：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trigger-public-build.ps1 `
  -PublicRepo lingy-Mg/Mg-Read `
  -Target windows,android
```

也可以在公开仓库 Actions 页面手动运行 `Public Build Bridge`，并手填 `source_repository` / `source_ref` / `source_sha`。

## 设计说明

- 公开仓库不保存闭源源码，只在 Actions 运行时临时 checkout 私库指定提交。
- Windows 与 Android 分开构建，最后统一收集并打密码压缩包发布到公开仓库 Release。
- Android 签名文件不再依赖私库中的本地 `key.properties` / `.jks`，而是由公开仓库 Secrets 在运行时临时写入。
- 模板默认启用 `pnpm`、Rust `Cargo/target`、Gradle 三层缓存，尽量复用 GitHub Actions 免费缓存来缩短后续构建时间。
- 当前模板优先覆盖 Windows 和 Android；Harmony / Linux 后续可以按同样模式扩展。
