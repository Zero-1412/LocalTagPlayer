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
