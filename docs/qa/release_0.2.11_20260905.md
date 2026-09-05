# v0.2.11 发布记录（2026-09-05）

- 源码基线：53aa5bd；发布准备仅修改版本及文档。
- 原工作区未提交修改保留，未纳入正式包。
- 使用既有 workflow_dispatch / publish_unsigned_release 路径，Windows 未签名，macOS 未签名且未公证。
- 待运行：发布说明预览、全量测试、analyze、Windows Debug 构建与启动、Windows/macOS Release 构建及资产校验。
- schema、FilterQuery / TagQueryService、filtered queue、thumbnail/media queue：本次发布准备 unchanged。
- user data：preserved；protected behaviors：preserved；unauthorized feature removal：none；mount and reachability：发布准备不修改 UI，既有原生验收缺口沿用 CURRENT_TASK。
- prompt impact：只处理正式包发布，保留既有门禁和未完成验收的真实状态。
