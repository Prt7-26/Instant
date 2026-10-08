# 直接分发与更新

当前阶段使用 DMG 直接分发。应用仍为 ad-hoc 本地签名，没有 Apple Developer ID 签名或公证；DMG 不会改变这个事实。当前构建仅支持 Apple Silicon，最低 macOS 26。

公开仓库：https://github.com/Prt7-26/Instant

安装包与 SHA-256 校验文件：https://github.com/Prt7-26/Instant/releases/latest

## 生成安装包

```sh
bash scripts/package-dmg.sh
```

重新构建应用并产生 `dist/Instant-<version>-<build>-<arch>.dmg` 及 `.dmg.sha256`。只打包已经验证过的 build/Instant.app 时使用 `--skip-build`。脚本检查应用签名完整性、验证磁盘映像；不会覆盖同名发布文件。

DMG 只包含 Instant.app、Applications 文件夹快捷方式和安装说明，不打包开发机上的偏好、会话文件或钥匙串。构建的 ad-hoc 签名校验通过不代表获得 Apple 信任或公证。

## 每次发布

1. 修改代码；在 Resources/Info.plist 更新 CFBundleShortVersionString（例如 0.1.1）并递增 CFBundleVersion（例如 2）。同一个已发布版本不替换二进制文件。
2. 运行 `bash scripts/test.sh`；构建 DMG；在另一台 Mac 或干净测试账户验证首次安装，以及从上一版升级。验证最早支持的 macOS 和当前系统。
3. 检查问答、翻译、流式滚动、快捷键、归档、缺少配置引导和失败处理；确认升级后配置、API Key、已有归档仍可使用。
4. 在固定下载页面发布 DMG、SHA-256 校验文件、版本号、系统与芯片要求、简短更新说明。保留此前稳定版本。
5. 当前用户需退出 Instant，下载新版并替换“应用程序”里的旧版。配置与会话在应用包外；仍需验证数据格式兼容性。ad-hoc 构建改变后，钥匙串可能再次要求用户授权。

## 建议的自动更新方案（尚未接入）

使用 MIT 许可的 Sparkle 2，在菜单栏右键菜单增加“检查更新…”，不增加主输入框元素。自动检查征得用户同意，更新安装前保存草稿与会话；回答生成中延后重启。

Sparkle 读取固定 HTTPS 地址的 appcast，下载并验证更新包。发布时生成新版包和更新摘要，使用专用 Ed25519 私钥签名，再先上传更新包、最后更新 appcast。用户确认后安装、重启。只需要静态文件托管，无需运行数据库或常驻后端。

可将二进制文件放在 GitHub Releases（发布二进制不要求公开应用源代码），appcast 使用长期稳定的 HTTPS 地址。面向国内用户时，要实测所选托管地址的可达性和下载速度。

更新公钥写入应用；私钥单独安全备份，不放进安装包或公开仓库。这种签名用于确认更新由发布者提供，不能替代 Apple Developer ID 和公证。没有 Developer ID 的情况下尤其不能丢失更新私钥，否则可能需要用户手动重新安装。

正式接入前需要确定：固定 appcast 地址，以及更新签名密钥的保存方式。当前代码没有内置更新检查；安装包通过 GitHub Releases 手动下载。

## 已核对的官方资料

- [Apple Developer ID](https://developer.apple.com/developer-id/)：站外分发签名与公证，获取证书需要开发者计划会员。
- [Apple 对未公证应用的说明](https://support.apple.com/102445)：未公证或无法验证开发者的应用可能被系统阻止打开。
- [Sparkle](https://sparkle-project.org/)：MIT 许可、自动更新框架。
- [Sparkle 配置与更新签名](https://sparkle-project.org/documentation/)：HTTPS、Ed25519 公钥/私钥与签名验证。
- [Sparkle 发布流程](https://sparkle-project.org/documentation/publishing/)：更新包、appcast、版本号及更新说明。
- [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)：托管带版本的可下载发布文件。

核对日期：2026-09-26。托管服务条款、系统规则和工具行为在实际发布前应再次确认。
