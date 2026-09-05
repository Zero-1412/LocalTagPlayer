# v0.2.11 发布记录（2026-09-05）

- 源码基线：53aa5bd；发布准备仅修改版本及文档。
- 原工作区未提交修改保留，未纳入正式包。
- 使用既有 workflow_dispatch / publish_unsigned_release 路径，Windows 未签名，macOS 未签名且未公证。
- 待运行：发布说明预览、全量测试、analyze、Windows Debug 构建与启动、Windows/macOS Release 构建及资产校验。
- schema、FilterQuery / TagQueryService、filtered queue、thumbnail/media queue：本次发布准备 unchanged。
- user data：preserved；protected behaviors：preserved；unauthorized feature removal：none；mount and reachability：发布准备不修改 UI，既有原生验收缺口沿用 CURRENT_TASK。
- prompt impact：只处理正式包发布，保留既有门禁和未完成验收的真实状态。

## 构建依赖归档恢复

- 首次 CI：729 项测试通过、5 项跳过，analyze 通过；Windows Debug 在下载 mpv 归档时失败，上游 URL 与 release API 均返回 404。
- 仓库构建依赖资产保存原归档，SHA-256 仍为 72b1b348458f632063ed92a967617a078dc05129635a1b929c61d121b0e3a802；仅更新下载地址，不改变后端版本、协议或业务行为。
- 重新运行完整发布 CI 后补记结果。

## 发布结果

- GitHub Actions 33950748824 全部成功；分支集成、全量 Flutter 测试、analyze、Windows Debug 构建与启动均通过，Windows/macOS Release 与打包通过，macOS Release 进程启动通过。
- v0.2.11 是公开非预发布的 Latest；标签准确指向 022619ebca1c00b9104105757a2f5a85adeffec8。
- Windows 安装器 133219304 bytes；SHA-256：7508c63065086331fee7fa2e8a7c794a81a671701adb23191ee89e04a46da3aa。
- macOS DMG 44224236 bytes；SHA-256：e83b0382889727c461547af276f8455ea5d6f38b1020614a6742ffcdafb0a511。
- 从公开 Release 下载两份校验文件，逐项与 GitHub 返回的资产摘要核对一致。
- 发布页：https://github.com/Zero-1412/LocalTagPlayer/releases/tag/v0.2.11
- 验证运行：https://github.com/Zero-1412/LocalTagPlayer/actions/runs/33950748824
- 本轮没有执行真实 Windows 安装升级或原生 UI 点击；CI 进程启动不替代这些验收。此前 CURRENT_TASK 的相关阻塞继续有效。
- 最终对抗式审查：schema、FilterQuery / TagQueryService、filtered queue、thumbnail/media queue unchanged；user data preserved；prompt impact satisfies first principles；protected behaviors preserved；unauthorized feature removal none；mount and reachability 不适用于版本和下载 URL 修改，未将 CI 启动冒充页面点击证据。
- 下一步：在可丢弃 Windows 环境完成安装升级和主要入口验收，继续处理既有大库性能缺口。
