<p align="center">
  <img src="docs/CleanZip.png" alt="CleanZip 应用图标" width="160">
</p>

# CleanZip · 清简压缩

一个极简的原生 macOS ZIP 压缩工具，让中文文件名更可靠地在 Windows 上解压。

拖入文件或文件夹 → 选择保存位置 → 生成 ZIP。支持多选、取消压缩和在 Finder 中显示结果。全程本地处理，无网络请求、无遥测、无需 Python 或第三方运行时。

## 安装

**推荐使用 [CleanZip-1.0.1-installer.pkg 安装器](https://github.com/0mobb0/macOS_compress_tool/raw/refs/heads/main/downloads/CleanZip-1.0.1-installer.pkg)**：双击，按系统安装向导继续，安装后在启动台搜索 **CleanZip**。

- 原生 `.pkg` 安装向导，包含中文欢迎页、说明和完成页。
- 固定安装到 `/Applications/CleanZip.app`，支持首次安装和更新已有版本；不会去覆盖放在其他位置的副本。
- 更新前提示退出正在运行的 CleanZip；系统可能要求管理员密码。
- 支持 **macOS 13 或更高版本，Apple Silicon 与 Intel**。
- 只安装应用，无额外安装脚本、后台服务或开机启动项，不改动你的源文件或 ZIP。

也可以下载 [ZIP 便携包](https://github.com/0mobb0/macOS_compress_tool/raw/refs/heads/main/downloads/CleanZip-1.0.1-universal.zip)，解压后手动将 `CleanZip.app` 拖入「应用程序」。

开源应用使用 ad-hoc 签名；`.pkg` 安装器尚未使用 Apple Developer ID Installer 签名，二者均未公证。若网络下载的安装器或应用被系统阻止，确认来源后，在「系统设置 → 隐私与安全性」中允许打开。无需关闭系统安全保护。

## 1.0.1 修复

修复压缩 Python 虚拟环境等目录时，遇到符号链接（如 `.venv-lattice/bin/python → python3`）就中止整个任务的问题。现在跳过链接并列出清单，保留普通文件。不跟随链接去读取项目外部的文件。单独选择链接而没有任何可打包项目时，会明确提示未生成 ZIP。

虚拟环境里的链接不会变成 Windows 可运行的 Python；分享源码后应在目标系统重新创建虚拟环境。如果需要完整保存链接结构用于 Mac 备份，此工具不适用。

## 为什么这样处理文件名？

ZIP 中的文件名编码需要明确告知解压程序。macOS 与 Windows 的工具对未标记编码及 Unicode 规范化的处理可能不同，并非每一个 macOS ZIP 都会乱码。

CleanZip 对所有条目同时写入：

- UTF-8 文件名及 ZIP 通用标志位 **bit 11**，本地头和中央目录一致；
- Info-ZIP **Unicode Path Extra Field (`0x7075`)**，带文件名 CRC-32；
- **NFC** 规范化文件名，保留中文、日文、韩文、重音字符和 emoji；
- 标准 **DEFLATE** 压缩与 CRC-32 校验，不改动文件内容。

自动排除 `.DS_Store`、`__MACOSX` 和 `._*` AppleDouble 文件；其余隐藏文件仍会保留，请在分享前检查内容。不会打包扩展属性、Finder 标签或资源叉，因此不适合用来备份依赖这些信息的 Mac 应用或旧式文档。

格式依据：[PKWARE ZIP 规范](https://support.pkware.com/pkzip/appnote)。微软对 UTF-8 标志位的说明：[ZipArchive 文件名编码](https://learn.microsoft.com/en-us/dotnet/api/system.io.compression.ziparchive.-ctor)。

## 兼容范围和保护措施

目标为支持标准 UTF-8 ZIP 的现代 Windows 解压程序。仅支持 GBK、忽略 UTF-8 标志位的旧工具无法保证；建议使用现代 Windows 内置解压功能或更新解压工具。该应用创建新 ZIP，不修复已有乱码 ZIP，也不转换文本文档内部编码。

- v1 使用 ZIP32：单个文件和最终 ZIP 均须 **小于 4 GiB**，最多 **65,534 个文件及目录**，不支持 ZIP64、分卷或密码。
- 遇到 Windows 非法字符、保留设备名、末尾空格或句点、超过 255 UTF-16 单元的名称、大小写或 NFC 重名时，停止并提示用户，不悄悄重命名。
- 符号链接会跳过，不跟随、不写入 ZIP；完成后显示跳过数量，并可查看完整清单。目录链接、失效链接和循环链接同样跳过，避免中止整个项目的压缩。特殊文件仍不支持；普通目录与空文件会保留。Windows 的长路径限制仍取决于目标系统和解压位置，建议使用较短的目标路径。
- 已存在的目标文件不会被覆盖。压缩先写同目录临时文件，成功后原子发布；取消或发生错误时清理临时文件。原子发布需要目标文件系统支持硬链接，建议先保存到本机 APFS/HFS+ 磁盘，再复制到移动硬盘。
- 不能将 ZIP 保存到所选目录内部。打包期间请避免修改源文件；普通文件的大小和修改时间变化会触发失败，但这不是文件系统快照。
- 正常退出时需要先完成或取消压缩；强制终止或断电可能留下 `.cleanzip-*.tmp` 临时文件，可在确认应用已退出后删除。

## 从源码构建

需要 Xcode 15 或更新版本及命令行工具。项目无远程 Swift Package 依赖，只链接 macOS 自带 zlib。

```sh
scripts/test.sh
scripts/build-app.sh
scripts/build-installer.sh
open dist/CleanZip.app
```

产物：`dist/CleanZip.app`、`dist/CleanZip-1.0.1-universal.zip` 和 `dist/CleanZip-1.0.1-installer.pkg`。构建脚本包含原生图标生成、应用签名校验、安装器载荷逐文件比对，并生成 SHA-256 校验文件。安装器版本和最低系统版本从应用读取。

命令行调试工具与应用共用压缩核心：

```sh
.build/debug/zipcheck /tmp/分享.zip /path/to/资料
```

## 验证

本地验证包括 18 项 XCTest，以及 Python `zipfile` 的 CRC/内容回读、ZIP 本地头与中央目录编码检查、Unicode 扩展字段校验、macOS `ditto` 解压比对和实际压缩率测试。样本包含中日韩文字、emoji、NFD 重音文件名、空格、空目录、空文件和随机二进制数据。

GitHub Actions 会把 macOS 应用核心生成的样本传到 Windows runner，用 PowerShell `Expand-Archive` 解压并逐一检查 Unicode 文件名及 SHA-256；这验证 Windows 解压 API，不等于 Windows Explorer 图形界面人工实测。**请以本仓库实际运行的绿色 CI 结果为准；Windows 自动测试状态请查看 [Actions](https://github.com/0mobb0/macOS_compress_tool/actions)。**

安装器使用系统 `pkgbuild` / `productbuild` 构建；`scripts/verify-installer.py` 解包检查目标路径、双架构、系统要求、中文资源、更新策略与应用内容一致性。`scripts/test-installer.sh` 只允许在临时 GitHub Actions runner 上运行，实际验证首次安装、重复安装清理旧文件、应用移位后的固定安装位置及防止降级。它不会在普通本机环境直接安装。

## 项目结构

- `Sources/CleanZip`：SwiftUI 原生界面
- `Sources/ZipCore`：文件筛选、Windows 名称检查、ZIP 头与中央目录
- `Sources/CZip`：64 KiB 缓冲区的流式 DEFLATE、CRC 和线程安全取消
- `installer`：原生安装向导配置和中文页面
- `Tests` / `scripts`：测试、跨平台验证和可重复构建

## 开源协议

[MIT](LICENSE) © 2026 0mobb0
