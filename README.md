# CleanZip · 清简压缩

一个极简的原生 macOS ZIP 压缩工具，让中文文件名更可靠地在 Windows 上解压。

拖入文件或文件夹 → 选择保存位置 → 生成 ZIP。支持多选、取消压缩和在 Finder 中显示结果。全程本地处理，无网络请求、无遥测、无需 Python 或第三方运行时。

## 安装

下载 [CleanZip-1.0.0-universal.zip](https://github.com/0mobb0/macOS_compress_tool/raw/refs/heads/main/downloads/CleanZip-1.0.0-universal.zip)，解压后将 `CleanZip.app` 拖入「应用程序」，双击打开。支持 **macOS 13 或更高版本，Apple Silicon 与 Intel**。

开源构建使用 ad-hoc 签名，尚未使用 Apple Developer ID 签名或公证。从网络下载后，macOS 可能阻止首次启动：确认来源后，在「系统设置 → 隐私与安全性」中允许打开。无需关闭 Gatekeeper，也不要移除系统级安全限制。

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
- 不支持符号链接和特殊文件；目录与空文件会保留。Windows 的长路径限制仍取决于目标系统和解压位置，建议使用较短的目标路径。
- 已存在的目标文件不会被覆盖。压缩先写同目录临时文件，成功后原子发布；取消或发生错误时清理临时文件。原子发布需要目标文件系统支持硬链接，建议先保存到本机 APFS/HFS+ 磁盘，再复制到移动硬盘。
- 不能将 ZIP 保存到所选目录内部。打包期间请避免修改源文件；普通文件的大小和修改时间变化会触发失败，但这不是文件系统快照。
- 正常退出时需要先完成或取消压缩；强制终止或断电可能留下 `.cleanzip-*.tmp` 临时文件，可在确认应用已退出后删除。

## 从源码构建

需要 Xcode 15 或更新版本及命令行工具。项目无远程 Swift Package 依赖，只链接 macOS 自带 zlib。

```sh
scripts/test.sh
scripts/build-app.sh
open dist/CleanZip.app
```

产物：`dist/CleanZip.app` 和 `dist/CleanZip-1.0.0-universal.zip`。构建脚本包含原生图标生成及签名校验。

命令行调试工具与应用共用压缩核心：

```sh
.build/debug/zipcheck /tmp/分享.zip /path/to/资料
```

## 验证

本地验证包括 13 项 XCTest，以及 Python `zipfile` 的 CRC/内容回读、ZIP 本地头与中央目录编码检查、Unicode 扩展字段校验、macOS `ditto` 解压比对和实际压缩率测试。样本包含中日韩文字、emoji、NFD 重音文件名、空格、空目录、空文件和随机二进制数据。

GitHub Actions 会把 macOS 应用核心生成的样本传到 Windows runner，用 PowerShell `Expand-Archive` 解压并逐一检查 Unicode 文件名及 SHA-256；这验证 Windows 解压 API，不等于 Windows Explorer 图形界面人工实测。**请以本仓库实际运行的绿色 CI 结果为准；Windows 自动测试状态请查看 [Actions](https://github.com/0mobb0/macOS_compress_tool/actions)。**

## 项目结构

- `Sources/CleanZip`：SwiftUI 原生界面
- `Sources/ZipCore`：文件筛选、Windows 名称检查、ZIP 头与中央目录
- `Sources/CZip`：64 KiB 缓冲区的流式 DEFLATE、CRC 和线程安全取消
- `Tests` / `scripts`：测试、跨平台验证和可重复构建

## 开源协议

[MIT](LICENSE) © 2026 0mobb0
