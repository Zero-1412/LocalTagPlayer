# Code signing policy

Local Tag Player 是采用 MIT License 发布的开源桌面应用。项目计划申请
SignPath Foundation 为开源项目提供的免费 Windows 代码签名服务。

## 签名声明

申请通过后，Windows 正式产物将使用以下声明：

> Free code signing provided by SignPath.io, certificate by SignPath Foundation.

签名只用于证明安装包来自本仓库受审核的自动构建，不代表 SignPath Foundation
为应用功能、内容或适用性提供担保。未签名的历史版本会在 Release 页面明确标注，
并提供 SHA-256 校验值。

## 项目角色

- Committer 与 reviewer：[Zero-1412](https://github.com/Zero-1412)
- Signing approver：[Zero-1412](https://github.com/Zero-1412)

当前项目由个人开发者维护，因此同一维护者承担上述角色。所有仓库访问和签名服务
访问都必须启用多因素认证；正式签名请求必须对应公开仓库中的已审核提交和可追溯
GitHub Actions 构建，不接受本地上传的未知二进制文件。

## 构建与审批规则

1. 正式产物只能从公开的 `Zero-1412/LocalTagPlayer` 仓库构建。
2. 发布提交必须位于 `master`，其它远程开发分支必须已经合入或明确处置。
3. 构建前必须通过全量测试、静态分析、Windows Debug 构建与启动冒烟。
4. 每次签名请求必须由 signing approver 人工批准。
5. 产品名和版本必须与 `pubspec.yaml` 及 Git 标签一致。
6. 不签署第三方项目的独立产物；随包开源依赖继续遵守各自许可证。

## 隐私

Local Tag Player 的媒体库、标签、收藏、播放记录和缓存默认只保存在用户本机，不会
上传到项目维护者或 SignPath。应用仅在启动后的更新检查中访问公开 GitHub Releases
接口，并在用户主动打开更新入口时访问对应下载页面。详细说明见
[README 的“本地数据与隐私”章节](README.md#本地数据与隐私)。

## 安全联系

代码签名、构建来源或发布产物存在可疑情况时，请通过
[GitHub Issues](https://github.com/Zero-1412/LocalTagPlayer/issues) 提交报告；
涉及敏感漏洞时不要公开披露利用细节，应先联系仓库维护者协调处理。
