# NVOFA CUDA 硬件光流真实执行验证
>
> 状态：历史 QA/实验记录。当前门禁与优先级以 `docs/qa/`、`ROADMAP.md` 和 QA manifest 为准。

日期：2026-07-28

## 结论

本机 NVIDIA Optical Flow 能力已从“驱动 DLL 与导出存在”推进到“真实硬件
execute 成功”。隔离探针在 RTX 4070 SUPER 上创建 CUDA context、NVOFA
session 和 GPU buffer，上传一对包含水平位移的灰度帧，实际调用
`nvOFExecute`，同步后回读到非零 S10.5 光流向量。Debug 与 Release 结果一致。

这项证据证明 NVOFA 光流 primitive 可执行，但不证明已经生成中间视频帧。
FRUC 还需要连续前后帧、目标时间戳、合成输出和播放队列所有权；RTX Video SDK
的 Super Resolution、Artifact Reduction、SDR→HDR 也是另一条独立能力链。

## 官方来源与零分发方式

公开头文件来自 NVIDIA 官方
[NVIDIAOpticalFlowSDK 仓库](https://github.com/NVIDIA/NVIDIAOpticalFlowSDK)，
固定提交：

```text
edb50da3cf849840d680249aa6dbef248ebce2ca
```

脚本只下载两个采用 BSD-3-Clause 声明的公开头文件，并验证原始文件摘要：

```text
nvOpticalFlowCommon.h
sha256 A83F6045E5C470B35A6C50672F92E082B78D55752FE51CC20EB1A2738BE05B9D

nvOpticalFlowCuda.h
sha256 07DEFC79637FB9893F2A06204972EAA6BCF9E5BEA400C88440439EBAAA39F115
```

文件只保存在 Git 忽略的
`build/nvofa-public-headers/<commit>`。仓库没有提交 NVIDIA 头文件；正式应用
没有复制这些文件、CUDA Toolkit 或探针可执行文件。CMake 目标使用单独开关、
`EXCLUDE_FROM_ALL` 且没有 install 规则。

NVIDIA 官方
[NVOFA Programming Guide](https://docs.nvidia.com/video-technologies/optical-flow-sdk/nvofa-programming-guide/index.html)
说明 Optical Flow Engine 是独立硬件引擎；官方
[FRUC Programming Guide](https://docs.nvidia.com/video-technologies/optical-flow-sdk/nvfruc-programming-guide/index.html)
则单独定义由连续输入帧和目标时间戳生成中间帧的 FRUC 流程。两者不能混称。

## 探针覆盖

探针不依赖已安装 CUDA Toolkit，使用一个仅包含 NVOFA 公开头所需句柄类型的
本地兼容层，并动态解析系统驱动：

1. 以 `LOAD_LIBRARY_SEARCH_SYSTEM32` 加载 `nvcuda.dll` 和
   `nvofapi64.dll`；
2. 初始化 CUDA Driver API，枚举设备并创建 context；
3. 读取 NVOFA 驱动最大 API，使用公开头的 API 2.0 创建函数表；
4. 创建 Optical Flow session，查询 grid 与宽高能力；
5. 创建两块 GRAYSCALE8 输入缓冲和一块 SHORT2 输出缓冲；
6. 按驱动 pitch 逐行上传 320×192 两帧；
7. 调用 `nvOFExecute` 并同步 CUDA context；
8. 按输出 pitch 回读 S10.5 向量，要求非零向量且水平分量至少达到一个像素；
9. 按 buffer、session、context、DLL 的顺序释放全部资源。

固定命令：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_nvofa_execute_probe.ps1 -Configuration Debug

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\run_nvofa_execute_probe.ps1 -Configuration Release
```

两种配置均输出：

```text
nvofa-execute=passed api=2.0 driver-max=5.0
device=NVIDIA GeForce RTX 4070 SUPER grid=4 frame=320x192
nonzero=3840 max-flow-x-s10.5=453 max-flow-y-s10.5=162
```

驱动版本为 NVIDIA 595.97。输出向量使用 S10.5，数值 32 表示一个像素；门禁
只要求稳定证明执行与位移响应，不用单一合成图宣称实际视频观感或 FRUC 质量。

## 完整验证

- `flutter analyze`：通过，无问题；
- `flutter test`：297 项通过，3 项按既有显式条件跳过；
- `flutter build windows --debug`：通过；
- NVOFA execute 探针：Debug/Release 均通过；
- 标准 Debug bundle：未发现 NVOFA、Optical Flow、CUDA 或 NVIDIA SDK 文件；
- PowerShell 脚本：语法解析通过。

本轮只新增隔离 QA 代码、构建门禁和文档，没有改变正式运行时业务代码或 UI，
因此没有用重复的播放器点击截图冒充新增运行时行为验证；最近一次
Windows child HWND 真实进入、返回和退出证据继续见
`docs/history/qa/2026-07/vapoursynth_r78_real_frames_nvofa_20260728.md`。

## 产品与架构边界

- 正式 runner 继续只暴露轻量的驱动/API/D3D11 能力快照，不在启动时创建 CUDA
  或 NVOFA session。
- Flutter、`PlayerService` 和 `PlayerBackend` 没有取得 DLL、CUDA context、
  GPU buffer 或 NVOFA 函数表。
- 现有本机视频增强插件 ABI v1 仍是单帧原位 D3D11 纹理处理；本轮没有错误地
  把多帧、时间戳或额外输出塞进 ABI v1。
- 默认 MediaKit、Windows 后端选择、filtered queue、当前 index、返回媒体库
  状态、SQLite、标签、缓存队列和用户数据均不变。

## 下一阶段门禁

1. 由用户或发布负责人完成 NVIDIA Developer Program 和 Optical Flow SDK
   实际下载包许可确认；
2. 先做不分发厂商文件的 FRUC 本机插件，明确拥有前帧、后帧、目标时间戳和
   中间帧输出；
3. 验证 seek、快速切换、全屏、退出、音视频同步以及初始化/执行失败回退；
4. 对真人面部、动画渐变、暗场三类自然片源完成关闭/开启六组 A/B 和掉帧测试；
5. RTX Video SDK 1.1 另建插件验证 VSR、Artifact Reduction 与 SDR→HDR，
   不复用 FRUC 状态，也不在许可和多片源门禁前增加用户入口。
