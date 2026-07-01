# Public Build Repo Template

这个模板用于新建一个公开仓库，让公开仓库通过 GitHub Actions 拉取当前私有 `Legado-Tauri` 指定 commit，再免费构建并发布 Windows / Android / Harmony 压缩包。

## 目录用途

- `.github/workflows/public-build.yml`
  - 公开仓库的 GitHub Actions 工作流。
- `scripts/prepare-public-build-artifacts.mjs`
  - 把各平台构建产物重命名成 ASCII 安全文件名，再上传给 Release job。
- `scripts/create-protected-archives.ps1`
  - 把 `.exe` / `.apk` / `.hap` 打成带密码的压缩包，再上传到公开仓库 Release。
- `scripts/build-release-notes.ps1`
  - 读取上一版公开 Release 的 `build-manifest.json`，自动统计这次相对上次打包新增了多少个 git 提交，并生成 Release 更新日志。
- `scripts/send-qq-message.py`
  - 使用 GitHub Actions Secrets 调用 QQ Bot 私聊接口，发送中文构建结果通知。

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
- `QQ_BOT_APP_ID`
  - QQ Bot 的 App ID；与下方两个 QQ secrets 一起配置后，会在工作流结束时发送中文私聊通知。
- `QQ_BOT_APP_SECRET`
  - QQ Bot 的 App Secret；只从 Actions Secrets 读取，不写入公开仓库文件。
- `QQ_BOT_USER_OPENID`
  - 接收 QQ 私聊通知的目标用户 OpenID。

## 触发方式

主路径应该是私库 GitHub Actions 自动触发：

- 私库新增 `Dispatch Public Build` workflow。
- 每次 `main` 分支 push 后，私库自动向公开仓库发送 `repository_dispatch`。
- 私库需配置：
  - Actions Secret: `PUBLIC_BUILD_REPO_PAT`
  - Actions Variable: `PUBLIC_BUILD_REPO=lingy-Mg/Mg-Read`
  - Actions Variable: `PUBLIC_BUILD_TARGETS=windows,android`

要自动加入 Harmony 时，再把：

- `PUBLIC_BUILD_TARGETS`
  - 改成 `windows,android,harmony`
  - 或直接改成 `all`

注意：

- Harmony 现在线上改为下载并校验公开可获取的 CLI 镜像 `commandline-tools-linux-x64-6.1.0.816.zip`，再把 `source/LegadoArkTS/local.properties` 中的 `hwsdk.dir` 指向解压后的 `command-line-tools/sdk`。
- 不再依赖公开容器里预装的旧 `hvigorw`；实际构建入口改为 CLI 提供的 `hvigorw`，并以 `ohpm install --all` + `hvigorw assembleHap` 为准。
- 如果公开仓库已经建好，私库模板更新后还需要把 `scripts/public-build-repo-template/.github/workflows/public-build.yml`、`scripts/public-build-repo-template/scripts/prepare-public-build-artifacts.mjs`、`scripts/public-build-repo-template/scripts/create-protected-archives.ps1` 以及 `scripts/public-build-repo-template/scripts/send-qq-message.py` 同步到公开仓库实际文件；只改私库模板不会自动修好线上 workflow。

手动脚本仅保留给补发或排障：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trigger-public-build.ps1 `
  -PublicRepo lingy-Mg/Mg-Read `
  -Target all
```

也可以在公开仓库 Actions 页面手动运行 `Public Build Bridge`，并手填 `source_repository` / `source_ref` / `source_sha`。

## 设计说明

- 公开仓库不保存闭源源码，只在 Actions 运行时临时 checkout 私库指定提交。
- Windows、Android、Harmony 分开构建，最后统一收集并打密码压缩包发布到公开仓库 Release。
- Release 说明会自动读取上一版公开 Release 的 `build-manifest.json`，按私库 `source_sha` 统计“从上次打包到现在”的提交数，并附上最近一批提交标题作为更新日志。
- QQ 通知凭据只放在 Actions Secrets；当 `QQ_BOT_APP_ID`、`QQ_BOT_APP_SECRET`、`QQ_BOT_USER_OPENID` 全部存在时，workflow 收尾阶段会把各目标和 Release 的成功/失败状态整理成中文报告后私聊发送。
- Android 签名文件不再依赖私库中的本地 `key.properties` / `.jks`，而是由公开仓库 Secrets 在运行时临时写入。
- Harmony workflow 会缓存 `~/.ohpm`、`~/.npm`、`source/LegadoArkTS/oh_modules`、`source/LegadoArkTS/.hvigor`、`source/LegadoArkTS/node_modules`，以复用 `ohpm` 与项目侧 `hvigor` 依赖。
- `both` 仍表示 `windows + android`，`all` 表示 `windows + android + harmony`，避免在未准备好 Harmony 工具链时误触发。
