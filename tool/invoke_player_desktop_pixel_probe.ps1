<#
.SYNOPSIS
  对 Windows 播放器窗口执行不落盘画面的桌面像素呈现延迟采样。

.DESCRIPTION
  本工具只从已显示、前台的目标窗口客户区读取经过 DWM 合成后的像素，并把中心
  视频区域读取为 24×14 的匿名 RGB 指纹。默认使用中心原生小裁剪，避免 4K 整块
  缩放或大量 GDI 调用本身成为高刷新测量瓶颈；其它模式只用于对照。它不保存截图、媒体路径或原始像素。
  同一个 QueryPerformanceCounter 时间基准用于 Win32 键盘输入和桌面采样，因此输出的
  inputDown/inputUp → firstPersistentPixelChange 才可以作为“实际呈现帧”证据。

  为避免播放中的自然运动被误判为 seek 结果，默认要求每次输入前画面静止。使用者应先
  暂停视频，再运行短按/快退基线；长按扫描可显式设定 HoldMilliseconds，并从静止画面
  开始。自动化长按从 Down 开始持续采样到真实 Up，报告首个持续桌面变化、按住期间
  的最长静止段与有效采样率；若首帧在 Up 前已出现，Up -> 首帧字段保持 null。这个
  约束是性能证据，不是播放器功能。
#>
[CmdletBinding()]
param(
  # 目标必须是已经显示的专用 Debug 窗口；不能传入通配符，防止误向其它应用发键。
  [string]$WindowTitle = 'local_tag_player',
  # 可选 PID 与窗口标题双重核验，推荐由专用 QA 启动器传入。
  [int]$ProcessId = 0,
  [ValidateSet('forward', 'backward', 'manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward', 'playPause', 'fullscreen', 'playerFullscreen', 'click', 'progressDrag', 'custom')]
  [string]$Action = 'forward',
  # custom 动作的 Win32 virtual-key；普通模式不接受隐式覆盖，保留可复现默认快捷键。
  [ValidateRange(0, 255)]
  [int]$VirtualKey = 0,
  # Flutter Windows 在部分 IME/DPI 组合下不会把 KEYEVENTF_SCANCODE 交给 Focus 链；
  # virtualKey 仍通过 SendInput 的真实输入队列发送，用于与该兼容性差异对照。
  [ValidateSet('scanCode', 'virtualKey')]
  [string]$KeyboardInjectionMode = 'scanCode',
  # 实体键盘模式不发送任何按键。Debug runner 在实际 FLUTTERVIEW 收到 J/L 消息时写入
  # 匿名 QPC 锚点，探针以同一时钟测量随后出现的 DWM 像素变化。
  [string]$NativeKeyboardEvidencePath = '',
  [ValidateRange(1000, 30000)]
  [int]$ManualInputTimeoutMilliseconds = 15000,
  # 长按实体键盘必须由原生 Down/Up QPC 证明；该阈值只约束 QA 证据，不改变播放器行为。
  [ValidateRange(300, 10000)]
  [int]$ManualLongHoldMinimumMilliseconds = 600,
  [ValidateRange(1, 30)]
  [int]$Samples = 7,
  [ValidateRange(0, 5000)]
  [int]$HoldMilliseconds = 0,
  # 真实 PlayerPage 的主进度轨道使用两端交替拖动；只在鼠标悬停已显式展开控制条后
  # 才记录按下时刻，不能把“唤起控制条”的动画混进 seek 呈现延迟。
  [ValidateRange(0.05, 0.95)]
  [double]$ProgressDragStartFraction = 0.28,
  [ValidateRange(0.05, 0.95)]
  [double]$ProgressDragEndFraction = 0.72,
  # 正常/全屏 PlayerPage 的可见 Slider 中线通常位于客户区底部约 90–110 个逻辑 px；
  # 探针会按目标窗口 DPI 转为物理坐标，默认 110 避免误把隐藏态 12px 点击条的
  # “单击定位”当作连续拖动。
  [ValidateRange(60, 240)]
  [int]$ProgressDragBottomInsetPixels = 110,
  [ValidateRange(20, 2000)]
  [int]$ProgressDragDurationMilliseconds = 180,
  # 可选：真实 PlayerPage 以 Debug-only 匿名回执确认完整 Slider 的 onChangeEnd；提供
  # 后缺回执即拒绝样本，防止隐藏点击条的像素变化误充拖动。
  [string]$ExpectedInputEvidencePath = '',
  # 真实 PlayerPage 的快捷键仅由其 FocusNode 接收。该开关在基线前向视频中心发送一次
  # 不触发播放切换的单击以取得焦点；准备动作不计入键盘输入到呈现帧的时钟。
  [switch]$PreparePlayerKeyboardFocus,
  [ValidateRange(30, 240)]
  [int]$FrameRate = 120,
  [ValidateRange(250, 15000)]
  [int]$PerSampleTimeoutMilliseconds = 5000,
  [ValidateRange(0, 2000)]
  [int]$SettleMilliseconds = 350,
  # 中心采样区相对初始静止画面的 RGB 平均差异阈值。小于该值的采样不能被当成新画面。
  [ValidateRange(0.1, 30.0)]
  [double]$PixelChangeThresholdPercent = 1.5,
  # 防止请求 120fps、实际只采样十几帧却宣称高刷新率体验。
  [ValidateRange(10, 240)]
  [int]$MinimumEffectiveCaptureFps = 80,
  # centerCrop 是单次原生小裁剪，避免 4K 整块缩放或 336 次 GetPixel 成为测量瓶颈；
  # distributed/scaled 仅保留作驱动差异对照。
  [ValidateSet('centerCrop', 'distributed', 'scaled')]
  [string]$PixelSamplingMode = 'centerCrop',
  [bool]$RequireStaticBaseline = $true,
  [string]$Output = '',
  [switch]$ValidateOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
  throw '桌面像素探针只支持 Windows。'
}

$nativeSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public sealed class DesktopPixelProbeSample
{
    public long qpcUs { get; set; }
    public long utcTicks { get; set; }
    public int clientWidth { get; set; }
    public int clientHeight { get; set; }
    public double differenceFromPreviousPercent { get; set; }
    public double differenceFromBaselinePercent { get; set; }
    public ulong fingerprint { get; set; }
}

public sealed class DesktopPixelProbePresentedChange
{
    public long qpcUs { get; set; }
    public long utcTicks { get; set; }
    public int clientWidth { get; set; }
    public int clientHeight { get; set; }
    public double differenceFromPreviousPercent { get; set; }
    public double differenceFromBaselinePercent { get; set; }
    public ulong fingerprint { get; set; }
}

public sealed class DesktopPixelProbeAction
{
    public int index { get; set; }
    public string resultEvidence { get; set; }
    public bool baselineStatic { get; set; }
    public double baselineMotionP95Percent { get; set; }
    public long keyDownQpcUs { get; set; }
    public long keyUpQpcUs { get; set; }
    public long physicalKeyUpQpcUs { get; set; }
    public int physicalKeyHoldDurationMs { get; set; }
    public bool manualHoldSatisfied { get; set; }
    public long firstChangedPixelQpcUs { get; set; }
    public long firstGeometryChangeQpcUs { get; set; }
    public int inputDownToFirstChangedPixelMs { get; set; }
    public int? inputUpToFirstChangedPixelMs { get; set; }
    public int inputDownToGeometryChangeMs { get; set; }
    public int inputUpToGeometryChangeMs { get; set; }
    public int maxUnchangedRunMs { get; set; }
    // GetDC/客户区句柄在窗口尺寸协调或 Texture 释放瞬间可能短暂不可读；只记录
    // 重试次数，不把重试期间的空样本伪装成帧或放宽首帧门禁。
    public int captureReadFailures { get; set; }
    // 只记录目标窗口线程的原生焦点类别，不写 HWND、标题或媒体信息。
    public string nativeFocusEvidence { get; set; }
    public bool inputUsesNativeQpcAnchor { get; set; }
    public bool inputSemanticConfirmed { get; set; }
    public string inputSemanticEvidence { get; set; }
    public bool passed { get; set; }
    public string failure { get; set; }
    public List<DesktopPixelProbeSample> samples { get; set; }
    // 长按/连续扫描保留后续 DWM 合成变化，供 trace 关联下一张实际画面；不保存原始像素。
    public List<DesktopPixelProbePresentedChange> presentedChanges { get; set; }
}

public sealed class DesktopPixelProbeReport
{
    public string evidence { get; set; }
    public string captureMethod { get; set; }
    public int requestedCaptureFps { get; set; }
    public double effectiveCaptureFps { get; set; }
    public int minimumEffectiveCaptureFps { get; set; }
    public bool captureRatePassed { get; set; }
    public int windowProcessId { get; set; }
    public int initialClientWidth { get; set; }
    public int initialClientHeight { get; set; }
    public int windowDpi { get; set; }
    public int geometryChanges { get; set; }
    public int captureReadFailures { get; set; }
    public int virtualKey { get; set; }
    public string inputMode { get; set; }
    public int holdMilliseconds { get; set; }
    public int manualLongHoldMinimumMilliseconds { get; set; }
    public double pixelChangeThresholdPercent { get; set; }
    public int successfulSamples { get; set; }
    public int timedOutSamples { get; set; }
    public int p50InputDownToPixelMs { get; set; }
    public int p95InputDownToPixelMs { get; set; }
    public int? p50InputUpToPixelMs { get; set; }
    public int? p95InputUpToPixelMs { get; set; }
    public int p50InputDownToGeometryMs { get; set; }
    public int p95InputDownToGeometryMs { get; set; }
    public int longestUnchangedRunMs { get; set; }
    public List<DesktopPixelProbeAction> actions { get; set; }
}

public static class DesktopPixelProbe
{
    private const int SRCCOPY = 0x00CC0020;
    private const int CAPTUREBLT = 0x40000000;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const int GridWidth = 24;
    private const int GridHeight = 14;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFOHEADER
    {
        public uint biSize;
        public int biWidth;
        public int biHeight;
        public ushort biPlanes;
        public ushort biBitCount;
        public uint biCompression;
        public uint biSizeImage;
        public int biXPelsPerMeter;
        public int biYPelsPerMeter;
        public uint biClrUsed;
        public uint biClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BITMAPINFO
    {
        public BITMAPINFOHEADER bmiHeader;
        public uint bmiColors;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr FindWindow(string className, string windowName);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool AttachThreadInput(uint attachThreadId, uint attachToThreadId, bool attach);
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
    [StructLayout(LayoutKind.Sequential)]
    private struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
    }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool GetGUIThreadInfo(uint threadId, ref GUITHREADINFO info);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int GetClassName(
        IntPtr hWnd,
        System.Text.StringBuilder className,
        int maxCount);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetFocus();
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint MapVirtualKey(uint code, uint mapType);
    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public UIntPtr dwExtraInfo;
    }
    [StructLayout(LayoutKind.Explicit)]
    private struct INPUTUNION
    {
        [FieldOffset(0)] public KEYBDINPUT keyboard;
        // SendInput 在 x64 上以最大 union 成员计算 INPUT cbSize；没有这个 32-byte
        // mouse 成员会传入错误的 32-byte keyboard-only 结构并被 Windows 拒绝。
        [FieldOffset(0)] public MOUSEINPUT mouse;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public INPUTUNION union;
    }
    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, INPUT[] inputs, int inputSize);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool StretchBlt(
        IntPtr hdcDest, int xDest, int yDest, int wDest, int hDest,
        IntPtr hdcSrc, int xSrc, int ySrc, int wSrc, int hSrc, int rop);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern uint GetPixel(IntPtr hdc, int x, int y);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteDC(IntPtr hdc);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateDIBSection(
        IntPtr hdc, ref BITMAPINFO bitmapInfo, uint usage,
        out IntPtr bits, IntPtr section, uint offset);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr objectHandle);
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteObject(IntPtr objectHandle);

    private sealed class PixelFrame
    {
        public byte[] Values;
        public int Width;
        public int Height;
        public ulong Fingerprint;
    }

    public static DesktopPixelProbeReport Run(
        string windowTitle,
        int expectedProcessId,
        int virtualKey,
        bool useVirtualKeyInjection,
        bool manualKeyboard,
        bool manualLongKeyboard,
        int manualLongHoldMinimumMilliseconds,
        bool mouseClick,
        bool mouseProgressDrag,
        bool preparePlayerKeyboardFocus,
        int sampleCount,
        int holdMilliseconds,
        double progressDragStartFraction,
        double progressDragEndFraction,
        int progressDragBottomInsetPixels,
        int progressDragDurationMilliseconds,
        string expectedInputEvidencePath,
        string nativeKeyboardEvidencePath,
        int manualInputTimeoutMilliseconds,
        int frameRate,
        int timeoutMilliseconds,
        int settleMilliseconds,
        double thresholdPercent,
        int minimumCaptureFps,
        bool requireStaticBaseline,
        bool geometryAction,
        string samplingMode)
    {
        if (String.IsNullOrWhiteSpace(windowTitle)) throw new ArgumentException("windowTitle");
        if (!mouseClick && !mouseProgressDrag && (virtualKey <= 0 || virtualKey > 255))
            throw new ArgumentOutOfRangeException("virtualKey");
        if (manualLongKeyboard && !manualKeyboard)
            throw new ArgumentException("长按实体键盘模式必须同时启用 manualKeyboard。");
        if (manualKeyboard && String.IsNullOrWhiteSpace(nativeKeyboardEvidencePath))
            throw new ArgumentException("实体键盘模式必须传入原生 QPC 匿名证据文件。");
        // 正式 PlayerPage 的自动化键盘也必须有页面语义回执；专用 Texture QA 未传该
        // 文件时保持旧的像素对照合同，避免把测试页内部按键当成产品输入证据。
        var keyboardSemanticRequired = !mouseClick && !mouseProgressDrag &&
            !manualKeyboard && !String.IsNullOrWhiteSpace(expectedInputEvidencePath);
        var window = FindWindow(null, windowTitle);
        if (window == IntPtr.Zero) throw new InvalidOperationException("未找到标题完全匹配的目标窗口。");
        if (!IsWindowVisible(window)) throw new InvalidOperationException("目标窗口不可见，拒绝采样或发送输入。");
        uint foundProcessId;
        GetWindowThreadProcessId(window, out foundProcessId);
        if (expectedProcessId > 0 && foundProcessId != (uint)expectedProcessId)
            throw new InvalidOperationException("窗口 PID 与调用方给定 PID 不一致，拒绝发送输入。");
        if (!BringToForeground(window))
            throw new InvalidOperationException("无法将目标窗口置前，拒绝向非前台窗口发送输入。");

        RECT initialRect;
        if (!GetClientRect(window, out initialRect)) throw new InvalidOperationException("无法读取目标窗口客户区。");
        var initialWidth = initialRect.Right - initialRect.Left;
        var initialHeight = initialRect.Bottom - initialRect.Top;
        var windowDpi = (int)GetDpiForWindow(window);
        if (initialWidth < 320 || initialHeight < 240)
        {
            // 独立 Debug QA 会话偶尔被 Windows 启动策略最小化。窗口标题与 PID 已双重
            // 匹配且刚通过前台核验时，先恢复一次再读取；不能把最小化客户区当性能样本。
            ShowWindow(window, 9); // SW_RESTORE
            Thread.Sleep(120);
            if (!GetClientRect(window, out initialRect))
                throw new InvalidOperationException("无法在恢复窗口后读取客户区。");
            initialWidth = initialRect.Right - initialRect.Left;
            initialHeight = initialRect.Bottom - initialRect.Top;
        }
        if (initialWidth < 320 || initialHeight < 240)
            throw new InvalidOperationException("目标窗口客户区过小，不能生成可靠视频像素证据。");
        if (preparePlayerKeyboardFocus)
        {
            // PlayerPage 视频表面的单击只请求其 FocusNode，不会调用播放切换；必须在
            // 静态基线和 QPC 计时之前完成，避免把焦点建立误计为 seek 呈现延迟。
            FocusPlayerKeyboard(window);
            Thread.Sleep(240);
        }

        var report = new DesktopPixelProbeReport {
            evidence = "desktop-composited-pixel-change",
            captureMethod = samplingMode == "distributed"
                ? "Win32 GetDC + distributed GetPixel from foreground client area; no screenshots retained"
                : samplingMode == "centerCrop"
                    ? "Win32 GetDC + native center-crop StretchBlt from foreground client area; no screenshots retained"
                    : "Win32 GetDC + scaled StretchBlt from foreground client area; no screenshots retained",
            requestedCaptureFps = frameRate,
            minimumEffectiveCaptureFps = minimumCaptureFps,
            windowProcessId = (int)foundProcessId,
            initialClientWidth = initialWidth,
            initialClientHeight = initialHeight,
            windowDpi = windowDpi,
            virtualKey = virtualKey,
            inputMode = manualKeyboard
                ? "manual-keyboard-native-qpc"
                : mouseClick
                ? "win32-mouse-click"
                : mouseProgressDrag
                    ? "win32-mouse-drag-progress-track"
                    : useVirtualKeyInjection
                        ? "win32-keyboard-virtual-key"
                        : "win32-keyboard-scancode",
            holdMilliseconds = holdMilliseconds,
            manualLongHoldMinimumMilliseconds = manualLongHoldMinimumMilliseconds,
            pixelChangeThresholdPercent = thresholdPercent,
            actions = new List<DesktopPixelProbeAction>()
        };

        var allCaptured = 0;
        var captureStartUs = NowUs();
        var excludedIdleUs = 0L;
        var lastCaptureUs = captureStartUs;
        var captureIntervalUs = Math.Max(1L, 1000000L / frameRate);
        PixelFrame previous = null;
        for (var index = 0; index < sampleCount; index++)
        {
            var action = new DesktopPixelProbeAction {
                index = index + 1,
                resultEvidence = geometryAction
                    ? "window-geometry-change"
                    : "desktop-composited-pixel-change",
                samples = new List<DesktopPixelProbeSample>(),
                presentedChanges = new List<DesktopPixelProbePresentedChange>(),
                failure = ""
            };
            var inputEvidenceMarkerUtc = DateTime.MinValue;
            var inputEvidenceMarkerLength = 0L;
            var nativeKeyboardEvidenceMarkerLength = 0L;
            if (mouseProgressDrag)
            {
                // 先把真实指针移动到轨道起点并等待控制条显示稳定，再采集静态基线。
                // 起终点逐样本互换，避免多次拖动都停在同一端导致“没有新画面”。
                var prepareStartedUs = NowUs();
                PrepareProgressDrag(
                    window,
                    index,
                    progressDragStartFraction,
                    progressDragEndFraction,
                    progressDragBottomInsetPixels);
                excludedIdleUs += Math.Max(0L, NowUs() - prepareStartedUs);
            }
            if (mouseProgressDrag || manualKeyboard || keyboardSemanticRequired)
            {
                // 键盘动作只需要记录语义文件的基线长度；不移动到 Slider，避免控制条
                // hover/重建在发送快捷键前重新竞争 PlayerPage FocusNode。
                previous = null;
                inputEvidenceMarkerUtc = LastWriteUtc(expectedInputEvidencePath);
                inputEvidenceMarkerLength = InputEvidenceLength(expectedInputEvidencePath);
                if (manualKeyboard)
                    nativeKeyboardEvidenceMarkerLength =
                        InputEvidenceLength(nativeKeyboardEvidencePath);
            }
            var baselineFrames = new List<PixelFrame>();
            var baselineDeltas = new List<double>();
            var baselineCount = Math.Max(5, frameRate / 4);
            PixelFrame baselinePrevious = previous;
            // 窗口重建/释放期间 GetClientRect 或桌面 DC 可能短暂失败。保留静态基线
            // 的帧数和阈值合同，只在一个有界窗口内重试；若仍无法取得足够帧，输出
            // 明确的 capture failure，而不是让异常退出覆盖根因。
            var baselineDeadlineUs = NowUs() + Math.Max(
                1000000L,
                (long)baselineCount * captureIntervalUs * 8L);
            while (baselineFrames.Count < baselineCount && NowUs() < baselineDeadlineUs)
            {
                PixelFrame baselineFrame;
                if (!TryCapture(window, samplingMode, out baselineFrame))
                {
                    action.captureReadFailures++;
                    report.captureReadFailures++;
                    Thread.Sleep(4);
                    continue;
                }
                allCaptured++;
                if (baselinePrevious != null) baselineDeltas.Add(DifferencePercent(baselinePrevious.Values, baselineFrame.Values));
                baselineFrames.Add(baselineFrame);
                previous = baselineFrame;
                WaitUntil(ref lastCaptureUs, captureIntervalUs);
            }
            if (baselineFrames.Count < baselineCount)
            {
                action.failure = "pixel_capture_unavailable";
                report.actions.Add(action);
                continue;
            }
            var baseline = baselineFrames[baselineFrames.Count - 1];
            action.baselineMotionP95Percent = Percentile(baselineDeltas, 0.95);
            action.baselineStatic = action.baselineMotionP95Percent < thresholdPercent;
            if (requireStaticBaseline && !action.baselineStatic)
            {
                action.failure = "baseline_not_static";
                report.actions.Add(action);
                continue;
            }

            var automatedKeyboardHoldActive = false;
            var automatedKeyboardHoldMode = false;
            long automatedKeyboardHoldReleaseUs = 0;
            long automatedKeyboardRepeatUs = 0;
            if (manualKeyboard)
            {
                action.inputUsesNativeQpcAnchor = true;
                // 等待操作者实体按键期间没有进行像素采样；必须从 capture-rate 分母剔除，
                // 否则 30 秒等待会把真实 120fps 采样误报为 2.5fps。
                var manualInputWaitStartedUs = NowUs();
                action.keyDownQpcUs = WaitForNativeKeyboardDownQpc(
                    nativeKeyboardEvidencePath,
                    nativeKeyboardEvidenceMarkerLength,
                    virtualKey == 0x4C ? "forward" : "backward",
                    manualInputTimeoutMilliseconds);
                excludedIdleUs += Math.Max(0L, action.keyDownQpcUs - manualInputWaitStartedUs);
                // 实体短按的松键消息可能在命令提交之后才到达，不能把它偷换成可比较的
                // KeyUp 延迟；本合同只输出 native WM_KEYDOWN -> DWM 首帧。
                action.keyUpQpcUs = action.keyDownQpcUs;
            }
            else
            {
                action.nativeFocusEvidence = DescribeTargetFocus(window);
                action.keyDownQpcUs = NowUs();
                if (mouseClick)
                {
                    SendMouseClick(window);
                }
                else if (mouseProgressDrag)
                {
                    SendProgressDrag(
                        window,
                        index,
                        progressDragStartFraction,
                        progressDragEndFraction,
                        progressDragBottomInsetPixels,
                        progressDragDurationMilliseconds);
                }
                else
                {
                    var scanCode = (byte)(MapVirtualKey((uint)virtualKey, 0) & 0xFF);
                    SendKeyboardInput(virtualKey, scanCode, false, useVirtualKeyInjection);
                    if (holdMilliseconds <= 0)
                    {
                        Thread.Sleep(35);
                        action.keyUpQpcUs = NowUs();
                        SendKeyboardInput(virtualKey, scanCode, true, useVirtualKeyInjection);
                    }
                    else
                    {
                        // 长按的桌面像素必须从 Down 开始采样；重复消息和 KeyUp 在下面
                        // 的同一采样循环中推进，不能先阻塞 holdMilliseconds 再把中间帧丢掉。
                        automatedKeyboardHoldActive = true;
                        automatedKeyboardHoldMode = true;
                        automatedKeyboardRepeatUs = action.keyDownQpcUs + 220000L;
                        automatedKeyboardHoldReleaseUs =
                            action.keyDownQpcUs + holdMilliseconds * 1000L;
                    }
                }
                if (mouseClick || mouseProgressDrag) action.keyUpQpcUs = NowUs();
            }
            long physicalKeyUpQpcUs = 0;
            var firstChangedObserved = false;
            long postFirstChangedDeadlineUs = 0;
            // 保持按键、鼠标 Down/Up 和样本间 settle 都没有进行桌面采样，不能把它们
            // 计入有效 capture fps，否则慢 seek 的等待会伪造“采样器自身掉帧”。
            if (!manualLongKeyboard && !automatedKeyboardHoldActive)
                excludedIdleUs += Math.Max(0L, action.keyUpQpcUs - action.keyDownQpcUs);

            var deadlineUs = (manualLongKeyboard || automatedKeyboardHoldActive
                ? action.keyDownQpcUs + holdMilliseconds * 1000L
                : action.keyUpQpcUs) +
                timeoutMilliseconds * 1000L;
            long firstChangedUs = 0;
            long lastPresentedChangeUs = 0;
            var changedConsecutively = 0;
            var unchangedRunStartUs = action.keyDownQpcUs;
            while (NowUs() < deadlineUs)
            {
                var nowUs = NowUs();
                if (automatedKeyboardHoldActive)
                {
                    if (nowUs >= automatedKeyboardRepeatUs)
                    {
                        // 重复消息让 Flutter 收到真实 KeyRepeat；不要用测试框架伪造。
                        var scanCode = (byte)(MapVirtualKey((uint)virtualKey, 0) & 0xFF);
                        SendKeyboardInput(virtualKey, scanCode, false, useVirtualKeyInjection);
                        automatedKeyboardRepeatUs += 70000L;
                    }
                    if (nowUs >= automatedKeyboardHoldReleaseUs)
                    {
                        action.keyUpQpcUs = NowUs();
                        var scanCode = (byte)(MapVirtualKey((uint)virtualKey, 0) & 0xFF);
                        SendKeyboardInput(virtualKey, scanCode, true, useVirtualKeyInjection);
                        automatedKeyboardHoldActive = false;
                    }
                }
                if (manualLongKeyboard && physicalKeyUpQpcUs <= 0)
                {
                    physicalKeyUpQpcUs = TryReadNativeKeyboardUpQpc(
                        nativeKeyboardEvidencePath,
                        nativeKeyboardEvidenceMarkerLength,
                        virtualKey == 0x4C ? "forward" : "backward",
                        action.keyDownQpcUs);
                    if (physicalKeyUpQpcUs > 0)
                    {
                        action.physicalKeyUpQpcUs = physicalKeyUpQpcUs;
                        action.keyUpQpcUs = physicalKeyUpQpcUs;
                        action.physicalKeyHoldDurationMs =
                            (int)Math.Max(0L, (physicalKeyUpQpcUs - action.keyDownQpcUs) / 1000L);
                        action.manualHoldSatisfied =
                            action.physicalKeyHoldDurationMs >= manualLongHoldMinimumMilliseconds;
                        if (firstChangedObserved)
                            postFirstChangedDeadlineUs = physicalKeyUpQpcUs + 250000L;
                    }
                }
                PixelFrame current;
                if (!TryCapture(window, samplingMode, out current))
                {
                    action.captureReadFailures++;
                    report.captureReadFailures++;
                    // 失败不是有效采样；短暂的 DWM/客户区切换只让出一个采样间隔，
                    // 仍受原始 deadline、captureRatePassed 和连续两帧变化合同约束。
                    Thread.Sleep(4);
                    continue;
                }
                allCaptured++;
                var previousDelta = previous == null ? 0.0 : DifferencePercent(previous.Values, current.Values);
                var baselineDelta = DifferencePercent(baseline.Values, current.Values);
                var sample = new DesktopPixelProbeSample {
                    qpcUs = nowUs,
                    utcTicks = DateTime.UtcNow.Ticks,
                    clientWidth = current.Width,
                    clientHeight = current.Height,
                    differenceFromPreviousPercent = previousDelta,
                    differenceFromBaselinePercent = baselineDelta,
                    fingerprint = current.Fingerprint
                };
                action.samples.Add(sample);
                // 第一张稳定新画面在 changedConsecutively==0 时记录；之后只要匿名
                // 指纹确实变化且仍远离静态基线，就按 20ms 最小间隔记录。连续播放时
                // 相邻视频帧可能只改变少量采样像素，不能用过高的差异阈值把它们误判
                // 成静止；这些条目仍只是 DWM 呈现变化，不冒充独立解码帧。
                var presentedChange = baselineDelta >= thresholdPercent &&
                    (changedConsecutively == 0 ||
                     (previous != null && current.Fingerprint != previous.Fingerprint));
                if (presentedChange &&
                    (lastPresentedChangeUs <= 0 || nowUs - lastPresentedChangeUs >= 20000L))
                {
                    action.presentedChanges.Add(new DesktopPixelProbePresentedChange {
                        qpcUs = nowUs,
                        utcTicks = sample.utcTicks,
                        clientWidth = current.Width,
                        clientHeight = current.Height,
                        differenceFromPreviousPercent = previousDelta,
                        differenceFromBaselinePercent = baselineDelta,
                        fingerprint = current.Fingerprint
                    });
                    lastPresentedChangeUs = nowUs;
                }
                if ((mouseProgressDrag || manualKeyboard || keyboardSemanticRequired) &&
                    !action.inputSemanticConfirmed)
                {
                    action.inputSemanticConfirmed = HasInputEvidenceAfter(
                        expectedInputEvidencePath,
                        inputEvidenceMarkerUtc,
                        inputEvidenceMarkerLength,
                        manualKeyboard || keyboardSemanticRequired
                            ? "\"event\":\"player_keyboard_event\""
                            : "\"event\":\"progress_slider_committed\"");
                    if (action.inputSemanticConfirmed)
                        action.inputSemanticEvidence = manualKeyboard || keyboardSemanticRequired
                            ? "player-keyboard-event"
                            : "player-progress-slider-commit";
                }
                var geometryChanged = current.Width != initialWidth || current.Height != initialHeight;
                if (geometryChanged) report.geometryChanges++;
                if (geometryAction && geometryChanged)
                {
                    action.firstGeometryChangeQpcUs = nowUs;
                    action.inputDownToGeometryChangeMs = (int)((nowUs - action.keyDownQpcUs) / 1000L);
                    action.inputUpToGeometryChangeMs = (int)((nowUs - action.keyUpQpcUs) / 1000L);
                    action.passed = true;
                    break;
                }
                if (baselineDelta >= thresholdPercent)
                {
                    changedConsecutively++;
                    if (changedConsecutively == 1) firstChangedUs = nowUs;
                }
                else
                {
                    changedConsecutively = 0;
                }
                if (previousDelta < thresholdPercent * 0.30)
                {
                    action.maxUnchangedRunMs = Math.Max(
                        action.maxUnchangedRunMs,
                        (int)((nowUs - unchangedRunStartUs) / 1000L));
                }
                else
                {
                    unchangedRunStartUs = nowUs;
                }
                previous = current;
                if (changedConsecutively >= 2)
                {
                    if (!firstChangedObserved)
                    {
                        action.firstChangedPixelQpcUs = firstChangedUs;
                        action.inputDownToFirstChangedPixelMs = (int)((firstChangedUs - action.keyDownQpcUs) / 1000L);
                        if (!manualKeyboard && action.keyUpQpcUs > 0)
                            action.inputUpToFirstChangedPixelMs =
                                (int)((firstChangedUs - action.keyUpQpcUs) / 1000L);
                        else
                            action.inputUpToFirstChangedPixelMs = null;
                        firstChangedObserved = true;
                    }
                    if (automatedKeyboardHoldMode &&
                        postFirstChangedDeadlineUs <= 0)
                    {
                        postFirstChangedDeadlineUs = nowUs + 250000L;
                    }
                    if (!manualLongKeyboard)
                    {
                        // 自动长按必须继续采样到真实 KeyUp，才能同时验证按住期间的
                        // 连续扫描与持续掉帧；首个稳定画面后保留 250ms 观察窗，
                        // 避免把单个 DWM 像素变化误称为持续呈现。
                        if (!automatedKeyboardHoldActive)
                        {
                            if (!automatedKeyboardHoldMode ||
                                postFirstChangedDeadlineUs <= 0 ||
                                nowUs >= postFirstChangedDeadlineUs)
                            {
                                action.passed = true;
                                break;
                            }
                        }
                    }
                    if (physicalKeyUpQpcUs > 0 && postFirstChangedDeadlineUs <= 0)
                        postFirstChangedDeadlineUs = physicalKeyUpQpcUs + 250000L;
                }
                if (!manualLongKeyboard && !automatedKeyboardHoldActive &&
                    firstChangedObserved)
                {
                    // 长按在按住期间已出现首帧时，KeyUp 后只需结束当前动作；若
                    // 首帧恰好在 KeyUp 后才出现，上面的 changedConsecutively 分支
                    // 已记录 Up -> 首帧。两种情况都不能继续空转到超时。
                    if (!automatedKeyboardHoldMode ||
                        postFirstChangedDeadlineUs <= 0 ||
                        nowUs >= postFirstChangedDeadlineUs)
                    {
                        action.passed = true;
                        break;
                    }
                }
                if (manualLongKeyboard && firstChangedObserved &&
                    physicalKeyUpQpcUs > 0 && postFirstChangedDeadlineUs > 0 &&
                    nowUs >= postFirstChangedDeadlineUs)
                {
                    action.passed = action.manualHoldSatisfied;
                    break;
                }
                WaitUntil(ref lastCaptureUs, captureIntervalUs);
            }
            if (automatedKeyboardHoldActive)
            {
                // 采样 deadline 可能先于 hold 结束；始终释放本轮刚注入的按键，避免
                // QA 进程异常时把按键状态泄漏到下一个独立会话。
                action.keyUpQpcUs = NowUs();
                var scanCode = (byte)(MapVirtualKey((uint)virtualKey, 0) & 0xFF);
                SendKeyboardInput(virtualKey, scanCode, true, useVirtualKeyInjection);
                automatedKeyboardHoldActive = false;
            }
            if (!action.passed) action.failure = geometryAction
                ? "geometry_change_timeout"
                : manualLongKeyboard && physicalKeyUpQpcUs <= 0
                    ? "manual_key_up_timeout"
                    : manualLongKeyboard && !action.manualHoldSatisfied
                        ? "manual_hold_too_short"
                        : "pixel_change_timeout";
            if (action.passed && mouseProgressDrag &&
                !String.IsNullOrWhiteSpace(expectedInputEvidencePath) &&
                !action.inputSemanticConfirmed)
            {
                // DWM 新画面本身不足以证明鼠标命中了完整 Slider；可能是隐藏态点击条或
                // 其它底部控件。缺少 Debug-only 匿名回执的样本不能进入拖动 p95。
                action.passed = false;
                action.failure = "progress_slider_semantic_evidence_timeout";
                action.inputSemanticEvidence = "missing";
            }
            if (action.passed && (manualKeyboard || keyboardSemanticRequired) &&
                !action.inputSemanticConfirmed)
            {
                // 原生消息锚点只证明消息进入 FLUTTERVIEW；还需页面匿名回执证明快捷键
                // 已走入 PlayerPage，不能把其他窗口处理的同名按键算作播放器呈现。
                action.passed = false;
                action.failure = "player_keyboard_semantic_evidence_timeout";
                action.inputSemanticEvidence = "missing";
            }
            if (settleMilliseconds > 0) {
                Thread.Sleep(settleMilliseconds);
                excludedIdleUs += settleMilliseconds * 1000L;
            }
            report.actions.Add(action);
        }
        var captureElapsedUs = Math.Max(1L, NowUs() - captureStartUs - excludedIdleUs);
        report.effectiveCaptureFps = Math.Round(allCaptured * 1000000.0 / captureElapsedUs, 1);
        report.captureRatePassed = report.effectiveCaptureFps >= minimumCaptureFps;
        foreach (var action in report.actions)
        {
            if (action.passed) report.successfulSamples++;
            else report.timedOutSamples++;
            report.longestUnchangedRunMs = Math.Max(report.longestUnchangedRunMs, action.maxUnchangedRunMs);
        }
        var downLatencies = new List<double>();
        var upLatencies = new List<double>();
        var geometryDownLatencies = new List<double>();
        foreach (var action in report.actions) if (action.passed) {
            if (action.resultEvidence == "desktop-composited-pixel-change") {
                downLatencies.Add(action.inputDownToFirstChangedPixelMs);
                // 长按首帧可能在按住期间已经出现，此时没有可定义的
                // Up -> 首帧延迟；nullable 结果必须从 Up 分位数中排除，不能
                // 由 PowerShell/C# 的默认值伪造成 0ms。
                if (!action.inputUsesNativeQpcAnchor &&
                    action.inputUpToFirstChangedPixelMs.HasValue)
                    upLatencies.Add(action.inputUpToFirstChangedPixelMs.Value);
            } else {
                geometryDownLatencies.Add(action.inputDownToGeometryChangeMs);
            }
        }
        report.p50InputDownToPixelMs = (int)Percentile(downLatencies, 0.50);
        report.p95InputDownToPixelMs = (int)Percentile(downLatencies, 0.95);
        report.p50InputUpToPixelMs = upLatencies.Count == 0
            ? (int?)null
            : (int)Percentile(upLatencies, 0.50);
        report.p95InputUpToPixelMs = upLatencies.Count == 0
            ? (int?)null
            : (int)Percentile(upLatencies, 0.95);
        report.p50InputDownToGeometryMs = (int)Percentile(geometryDownLatencies, 0.50);
        report.p95InputDownToGeometryMs = (int)Percentile(geometryDownLatencies, 0.95);
        return report;
    }

    /**
     * 仅把桌面合成窗口短暂不可读归类为可重试采集失败。
     *
     * 这里不能吞掉门禁结果：调用方仍受动作 deadline、静态基线、两帧变化和有效
     * capture fps 限制；连续不可读会留下 pixel_capture_unavailable/低采样证据。
     */
    private static bool TryCapture(IntPtr window, string samplingMode, out PixelFrame frame)
    {
        try
        {
            frame = Capture(window, samplingMode);
            return true;
        }
        catch (InvalidOperationException)
        {
            frame = null;
            return false;
        }
    }

    private static PixelFrame Capture(IntPtr window, string samplingMode)
    {
        RECT client;
        if (!GetClientRect(window, out client)) throw new InvalidOperationException("采样期间无法读取客户区。");
        var width = client.Right - client.Left;
        var height = client.Bottom - client.Top;
        if (width < 320 || height < 240) throw new InvalidOperationException("采样期间客户区过小。");
        var origin = new POINT { X = 0, Y = 0 };
        if (!ClientToScreen(window, ref origin)) throw new InvalidOperationException("采样期间无法转换客户区坐标。");
        // 中心 60% 避开窗口标题、控制条、鼠标提示和侧栏；保留最终 DWM 合成的视频像素。
        var roiX = origin.X + (int)Math.Round(width * 0.20);
        var roiY = origin.Y + (int)Math.Round(height * 0.20);
        var roiWidth = Math.Max(1, (int)Math.Round(width * 0.60));
        var roiHeight = Math.Max(1, (int)Math.Round(height * 0.60));
        var sourceDc = GetDC(IntPtr.Zero);
        if (sourceDc == IntPtr.Zero) throw new InvalidOperationException("无法取得桌面 DC。");
        if (samplingMode == "distributed")
        {
            try
            {
                // 不复制 4K 的整块 ROI。以均匀分布的 24×14 个单像素直接生成匿名
                // RGB 指纹，仍然读取最终 DWM 桌面合成，但将测量器本身的缩放开销降到最低。
                var values = new byte[GridWidth * GridHeight * 3];
                ulong hash = 1469598103934665603UL;
                var offset = 0;
                for (var y = 0; y < GridHeight; y++)
                {
                    var sampleY = roiY + Math.Min(
                        roiHeight - 1,
                        Math.Max(0, (int)Math.Round((y + 0.5) * roiHeight / GridHeight)));
                    for (var x = 0; x < GridWidth; x++)
                    {
                        var sampleX = roiX + Math.Min(
                            roiWidth - 1,
                            Math.Max(0, (int)Math.Round((x + 0.5) * roiWidth / GridWidth)));
                        var color = GetPixel(sourceDc, sampleX, sampleY);
                        if (color == 0xFFFFFFFF) throw new InvalidOperationException("桌面分布式像素读取失败。");
                        var red = (byte)(color & 0xFF);
                        var green = (byte)((color >> 8) & 0xFF);
                        var blue = (byte)((color >> 16) & 0xFF);
                        values[offset++] = red;
                        values[offset++] = green;
                        values[offset++] = blue;
                        hash ^= red; hash *= 1099511628211UL;
                        hash ^= green; hash *= 1099511628211UL;
                        hash ^= blue; hash *= 1099511628211UL;
                    }
                }
                return new PixelFrame { Values = values, Width = width, Height = height, Fingerprint = hash };
            }
            finally
            {
                ReleaseDC(IntPtr.Zero, sourceDc);
            }
        }
        var targetDc = CreateCompatibleDC(sourceDc);
        if (targetDc == IntPtr.Zero)
        {
            ReleaseDC(IntPtr.Zero, sourceDc);
            throw new InvalidOperationException("无法创建桌面采样 DC。");
        }
        var bitmapInfo = new BITMAPINFO {
            bmiHeader = new BITMAPINFOHEADER {
                biSize = (uint)Marshal.SizeOf(typeof(BITMAPINFOHEADER)),
                biWidth = GridWidth,
                // 负高度让 DIB 按屏幕顺序从上到下写入，避免伪造的翻转差异。
                biHeight = -GridHeight,
                biPlanes = 1,
                biBitCount = 32,
                biCompression = 0,
                biSizeImage = (uint)(GridWidth * GridHeight * 4)
            }
        };
        IntPtr bitmapBits;
        var bitmap = CreateDIBSection(targetDc, ref bitmapInfo, 0, out bitmapBits, IntPtr.Zero, 0);
        if (bitmap == IntPtr.Zero || bitmapBits == IntPtr.Zero)
        {
            DeleteDC(targetDc);
            ReleaseDC(IntPtr.Zero, sourceDc);
            throw new InvalidOperationException("无法创建桌面采样 DIB。");
        }
        var previousBitmap = SelectObject(targetDc, bitmap);
        try
        {
            var sourceX = roiX;
            var sourceY = roiY;
            var sourceWidth = roiWidth;
            var sourceHeight = roiHeight;
            if (samplingMode == "centerCrop")
            {
                // 目标与源完全同尺寸，驱动只复制中央小块；它保留真实桌面像素证据，
                // 但不会为每一帧缩放 4K ROI 或发起数百次 GDI round-trip。
                sourceWidth = GridWidth;
                sourceHeight = GridHeight;
                sourceX = origin.X + Math.Max(0, (width - sourceWidth) / 2);
                sourceY = origin.Y + Math.Max(0, (height - sourceHeight) / 2);
            }
            if (!StretchBlt(
                targetDc, 0, 0, GridWidth, GridHeight, sourceDc,
                sourceX, sourceY, sourceWidth, sourceHeight, SRCCOPY | CAPTUREBLT))
                throw new InvalidOperationException("桌面像素复制失败。");
            var raw = new byte[GridWidth * GridHeight * 4];
            Marshal.Copy(bitmapBits, raw, 0, raw.Length);
            var values = new byte[GridWidth * GridHeight * 3];
            ulong hash = 1469598103934665603UL;
            var offset = 0;
            var rawOffset = 0;
            while (rawOffset < raw.Length)
            {
                // 32bpp BI_RGB 内存是 BGRA；匿名指纹统一保存 RGB。
                var blue = raw[rawOffset++];
                var green = raw[rawOffset++];
                var red = raw[rawOffset++];
                rawOffset++; // alpha/reserved
                values[offset++] = red;
                values[offset++] = green;
                values[offset++] = blue;
                hash ^= red; hash *= 1099511628211UL;
                hash ^= green; hash *= 1099511628211UL;
                hash ^= blue; hash *= 1099511628211UL;
            }
            return new PixelFrame { Values = values, Width = width, Height = height, Fingerprint = hash };
        }
        finally
        {
            if (previousBitmap != IntPtr.Zero) SelectObject(targetDc, previousBitmap);
            DeleteObject(bitmap);
            DeleteDC(targetDc);
            ReleaseDC(IntPtr.Zero, sourceDc);
        }
    }

    /**
     * Windows 会阻止后台进程直接夺取焦点。QA 启动器与 Flutter 测试属于不同进程时，
     * 仅在当前前台线程短暂 AttachThreadInput 后尝试激活目标，并在解除关联后再次核验。
     * 失败就拒绝输入；绝不退化为向后台 HWND PostMessage 键盘消息。
     */
    private static bool BringToForeground(IntPtr window)
    {
        if (GetForegroundWindow() == window) return true;
        var foreground = GetForegroundWindow();
        uint ignored;
        var targetThread = GetWindowThreadProcessId(window, out ignored);
        var foregroundThread = foreground == IntPtr.Zero
            ? 0
            : GetWindowThreadProcessId(foreground, out ignored);
        var currentThread = GetCurrentThreadId();
        var attachedToTarget = targetThread != 0 && targetThread != currentThread &&
            AttachThreadInput(currentThread, targetThread, true);
        var attachedToForeground = foregroundThread != 0 && foregroundThread != currentThread &&
            foregroundThread != targetThread && AttachThreadInput(currentThread, foregroundThread, true);
        try
        {
            ShowWindow(window, 5); // SW_SHOW：不改变最小化/最大化语义。
            BringWindowToTop(window);
            SetForegroundWindow(window);
            Thread.Sleep(60);
            return GetForegroundWindow() == window;
        }
        finally
        {
            if (attachedToForeground) AttachThreadInput(currentThread, foregroundThread, false);
            if (attachedToTarget) AttachThreadInput(currentThread, targetThread, false);
        }
    }

    /** 使用真实 scan-code 走 Windows 输入队列；不能用 PostMessage 假装收到物理按键。 */
    private static void SendKeyboardScan(byte scanCode, bool keyUp)
    {
        const uint inputKeyboard = 1;
        const uint keyEventfScancode = 0x0008;
        var flags = keyEventfScancode | (keyUp ? KEYEVENTF_KEYUP : 0);
        var input = new INPUT {
            type = inputKeyboard,
            union = new INPUTUNION {
                keyboard = new KEYBDINPUT {
                    wVk = 0,
                    wScan = scanCode,
                    dwFlags = flags,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };
        if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(INPUT))) != 1)
            throw new InvalidOperationException("SendInput 未能将 scan-code 写入前台 Windows 输入队列。");
    }

    /** 使用真实 SendInput virtual-key 走前台队列，作为 Flutter Windows scan-code 兼容性对照。 */
    private static void SendKeyboardVirtualKey(int virtualKey, bool keyUp)
    {
        const uint inputKeyboard = 1;
        var input = new INPUT {
            type = inputKeyboard,
            union = new INPUTUNION {
                keyboard = new KEYBDINPUT {
                    wVk = (ushort)virtualKey,
                    wScan = 0,
                    dwFlags = keyUp ? KEYEVENTF_KEYUP : 0,
                    time = 0,
                    dwExtraInfo = UIntPtr.Zero
                }
            }
        };
        if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(INPUT))) != 1)
            throw new InvalidOperationException("SendInput 未能将 virtual-key 写入前台 Windows 输入队列。");
    }

    private static void SendKeyboardInput(
        int virtualKey,
        byte scanCode,
        bool keyUp,
        bool useVirtualKeyInjection)
    {
        if (useVirtualKeyInjection) {
            SendKeyboardVirtualKey(virtualKey, keyUp);
        } else {
            SendKeyboardScan(scanCode, keyUp);
        }
    }

    /**
     * 点击客户区底部中央的 QA 交互入口。该位置由专用测试页固定提供，中心 60% 的
     * 视频采样区不含此按钮。仍通过 SendInput 进入前台窗口的真实鼠标输入链。
     */
    private static void SendMouseClick(IntPtr window)
    {
        RECT client;
        if (!GetClientRect(window, out client)) throw new InvalidOperationException("无法读取鼠标输入客户区。");
        var point = new POINT {
            X = (client.Right - client.Left) / 2,
            Y = Math.Max(1, (client.Bottom - client.Top) - 38)
        };
        if (!ClientToScreen(window, ref point)) throw new InvalidOperationException("无法转换鼠标输入坐标。");
        if (!SetCursorPos(point.X, point.Y)) throw new InvalidOperationException("无法移动 QA 鼠标到目标窗口。");
        // Flutter 手势层需要可观测的 Down → Up 时序；同一批两个输入在某些测试窗口中
        // 会被压缩成未命中的鼠标状态，因此分包并保留最小人类点击间隔。
        Thread.Sleep(30);
        SendMouseInput(0x0002); // MOUSEEVENTF_LEFTDOWN
        Thread.Sleep(35);
        SendMouseInput(0x0004); // MOUSEEVENTF_LEFTUP
    }

    /**
     * 激活真实 PlayerPage 窗口并点击视频上方区域，让页面 FocusNode 接收键盘。
     * 点击点刻意避开底部控制条/Slider；不能用窗口底部的通用点击来准备焦点，
     * 否则后续 J/L 可能被 Slider 或其它控件夺走并记录为输入语义失败。
     */
    private static void FocusPlayerKeyboard(IntPtr window)
    {
        RECT client;
        if (!GetClientRect(window, out client))
            throw new InvalidOperationException("无法读取真实 PlayerPage 焦点客户区。");
        var point = new POINT {
            X = Math.Max(1, (client.Right - client.Left) / 2),
            Y = Math.Max(1, (client.Bottom - client.Top) / 3)
        };
        if (!BringToForeground(window) ||
            !ClientToScreen(window, ref point) ||
            !SetCursorPos(point.X, point.Y))
            throw new InvalidOperationException("无法将焦点准备鼠标移动到真实 PlayerPage 视频表面。");
        Thread.Sleep(30);
        SendMouseInput(0x0002); // MOUSEEVENTF_LEFTDOWN
        Thread.Sleep(35);
        SendMouseInput(0x0004); // MOUSEEVENTF_LEFTUP
    }

    /** 诊断目标窗口线程实际持有的原生焦点类别，避免把 FocusNode 握手当成 Win32 焦点。 */
    private static string DescribeTargetFocus(IntPtr window)
    {
        uint ignoredProcessId;
        var threadId = GetWindowThreadProcessId(window, out ignoredProcessId);
        if (threadId == 0)
            return "unavailable";
        var info = new GUITHREADINFO {
            cbSize = Marshal.SizeOf(typeof(GUITHREADINFO))
        };
        if (!GetGUIThreadInfo(threadId, ref info))
        {
            // 某些 Flutter runner 生命周期中跨线程查询可能暂时失败；短暂挂接
            // 目标消息队列只读取 GetFocus，仍不向目标线程投递任何消息。
            var currentThreadId = GetCurrentThreadId();
            var attached = threadId != currentThreadId &&
                AttachThreadInput(currentThreadId, threadId, true);
            try
            {
                return DescribeFocusHandle(window, GetFocus());
            }
            finally
            {
                if (attached) AttachThreadInput(currentThreadId, threadId, false);
            }
        }
        return DescribeFocusHandle(window, info.hwndFocus);
    }

    private static string DescribeFocusHandle(IntPtr window, IntPtr focus)
    {
        if (focus == IntPtr.Zero)
            return "no-focus";
        if (focus == window)
            return "top-level-window";
        var className = new System.Text.StringBuilder(128);
        var length = GetClassName(focus, className, className.Capacity);
        return length > 0 ? "child-class:" + className.ToString() : "child-window";
    }

    /**
     * 为正式 PlayerPage 的主进度轨道准备真实指针位置。
     *
     * 控制条隐藏时，视频表面底部已有独立命中条，但完整 Slider 仅在 hover 后挂载。
     * 因此必须在基线之前移动并等待，输入计时只覆盖 Down -> Move -> Up 与最终新画面。
     */
    private static void PrepareProgressDrag(
        IntPtr window,
        int actionIndex,
        double startFraction,
        double endFraction,
        int bottomInsetPixels)
    {
        var forward = actionIndex % 2 == 0;
        MoveCursorToProgressTrack(
            window,
            forward ? startFraction : endFraction,
            bottomInsetPixels);
        // PlayerPage 控制条的显隐动画最长 200ms；为避免 PointerDown 落在仍处于
        // IgnorePointer 状态的透明树上，等待两帧余量。该时间被调用方从测量窗口排除。
        Thread.Sleep(360);
    }

    /**
     * 逐样本交替方向拖过真实 PlayerPage 底部进度轨道。
     *
     * 这不是 widget test 的 `drag`：Down/Move/Up 全部经 Win32 SendInput 进入前台窗口，
     * Flutter Slider 仍按正式路径只在 Up 时提交一次精确 seek。
     */
    private static void SendProgressDrag(
        IntPtr window,
        int actionIndex,
        double startFraction,
        double endFraction,
        int bottomInsetPixels,
        int durationMilliseconds)
    {
        var forward = actionIndex % 2 == 0;
        var from = forward ? startFraction : endFraction;
        var to = forward ? endFraction : startFraction;
        var start = ProgressTrackPoint(window, from, bottomInsetPixels);
        var end = ProgressTrackPoint(window, to, bottomInsetPixels);
        if (!SetCursorPos(start.X, start.Y))
            throw new InvalidOperationException("无法移动鼠标到正式 PlayerPage 进度轨道。");
        SendMouseInput(0x0002); // MOUSEEVENTF_LEFTDOWN
        const int steps = 12;
        var stepDelay = Math.Max(1, durationMilliseconds / steps);
        for (var step = 1; step <= steps; step++)
        {
            var x = start.X + (end.X - start.X) * step / steps;
            var y = start.Y + (end.Y - start.Y) * step / steps;
            if (!SetCursorPos(x, y))
                throw new InvalidOperationException("无法在正式 PlayerPage 进度轨道上移动鼠标。");
            Thread.Sleep(stepDelay);
        }
        SendMouseInput(0x0004); // MOUSEEVENTF_LEFTUP
    }

    private static void MoveCursorToProgressTrack(
        IntPtr window,
        double fraction,
        int bottomInsetPixels)
    {
        var point = ProgressTrackPoint(window, fraction, bottomInsetPixels);
        if (!SetCursorPos(point.X, point.Y))
            throw new InvalidOperationException("无法移动鼠标到正式 PlayerPage 进度轨道。");
    }

    private static POINT ProgressTrackPoint(
        IntPtr window,
        double fraction,
        int bottomInsetPixels)
    {
        RECT client;
        if (!GetClientRect(window, out client))
            throw new InvalidOperationException("无法读取正式 PlayerPage 的客户区。");
        var width = client.Right - client.Left;
        var height = client.Bottom - client.Top;
        if (width < 320 || height < 240)
            throw new InvalidOperationException("正式 PlayerPage 客户区过小，不能拖动进度轨道。");
        var clampedFraction = Math.Max(0.05, Math.Min(0.95, fraction));
        var point = new POINT {
            X = Math.Max(1, Math.Min(width - 2, (int)Math.Round(width * clampedFraction))),
            // Flutter 控制条使用逻辑像素，GetClientRect/SendInput 则使用物理像素。
            // 把调用方给出的逻辑底部间距按目标窗口 DPI 转换，避免 150% DPI 时落入
            // Slider 下方的传输按钮行；不同布局仍可显式调整，不能把失败坐标伪造成性能。
            Y = Math.Max(1, height - Math.Max(1, (int)Math.Round(
                bottomInsetPixels * Math.Max(1.0, GetDpiForWindow(window) / 96.0))))
        };
        if (!ClientToScreen(window, ref point))
            throw new InvalidOperationException("无法转换正式 PlayerPage 进度轨道坐标。");
        return point;
    }

    /** 读取 QA 回执文件的最后写入时刻；空路径保持 MinValue，允许只做像素实验。 */
    private static DateTime LastWriteUtc(string path)
    {
        if (String.IsNullOrWhiteSpace(path) || !File.Exists(path))
            return DateTime.MinValue;
        try { return File.GetLastWriteTimeUtc(path); }
        catch { return DateTime.MinValue; }
    }

    private static long InputEvidenceLength(string path)
    {
        if (String.IsNullOrWhiteSpace(path) || !File.Exists(path)) return 0L;
        try { return new FileInfo(path).Length; }
        catch { return 0L; }
    }

    /**
     * 只接受本次 PointerDown 之后新增的匿名完整 Slider 提交事件。
     *
     * 不返回文件内容，也不把路径写进报告；文件不存在时交给调用方是否将语义确认设为
     * 必需，避免普通手工像素观察被强制绑定到 Debug QA 环境变量。
     */
    private static bool HasInputEvidenceAfter(
        string path,
        DateTime markerUtc,
        long markerLength,
        string expectedEventFragment)
    {
        if (String.IsNullOrWhiteSpace(path) || !File.Exists(path)) return false;
        try
        {
            if (File.GetLastWriteTimeUtc(path) < markerUtc) return false;
            var content = File.ReadAllText(path);
            if (content.Length <= markerLength) return false;
            return content.Substring((int)Math.Min(markerLength, content.Length))
                .Contains(expectedEventFragment);
        }
        catch { return false; }
    }

    /**
     * 等待 Flutter 实际取得焦点的子 HWND 所写出的本次实体键盘 Down QPC。
     *
     * 文件轮询只用来发现事件；计时锚点使用事件内的共享 QPC，因此文件系统调度不会被
     * 误计入 input -> DWM 呈现延迟。文件内容只包含固定动作枚举，不含真实按键或媒体。
     */
    private static bool TryReadQpcUs(string line, out long qpcUs)
    {
        qpcUs = 0;
        const string qpcMarker = "\"qpcUs\":";
        var start = line.IndexOf(qpcMarker, StringComparison.Ordinal);
        if (start < 0) return false;
        start += qpcMarker.Length;
        // 当前原生侧车同时写 qpcUs 与 utcUs；qpcUs 不保证是 JSON 最后一个字段。
        // 只截取到下一个逗号或对象结束，避免把后续字段拼进 Int64.TryParse。
        var comma = line.IndexOf(',', start);
        var end = line.IndexOf('}', start);
        if (comma >= 0 && (end < 0 || comma < end)) end = comma;
        var text = end < 0 ? line.Substring(start) : line.Substring(start, end - start);
        return Int64.TryParse(text.Trim(), out qpcUs) && qpcUs > 0;
    }

    private static long WaitForNativeKeyboardDownQpc(
        string path,
        long markerLength,
        string expectedAction,
        int timeoutMilliseconds)
    {
        var deadlineUs = NowUs() + timeoutMilliseconds * 1000L;
        while (NowUs() < deadlineUs)
        {
            try
            {
                if (File.Exists(path))
                {
                    var content = File.ReadAllText(path);
                    if (content.Length > markerLength)
                    {
                        var recent = content.Substring(
                            (int)Math.Min(markerLength, content.Length));
                        var lines = recent.Split(new[] { '\r', '\n' },
                            StringSplitOptions.RemoveEmptyEntries);
                        foreach (var line in lines)
                        {
                            if (!line.Contains("\"event\":\"native_keyboard_message\"") ||
                                !line.Contains("\"action\":\"" + expectedAction + "\"") ||
                                !line.Contains("\"phase\":\"down\""))
                                continue;
                            long qpcUs;
                            if (TryReadQpcUs(line, out qpcUs))
                                return qpcUs;
                        }
                    }
                }
            }
            catch
            {
                // 写入与读取刚好交叠时下一毫秒重试；不能因暂态共享冲突改用本机时间。
            }
            Thread.Sleep(1);
        }
        throw new TimeoutException("未在时限内收到实体键盘的匿名 FLUTTERVIEW QPC 锚点。");
    }

    /**
     * 非阻塞读取本次实体长按的 KeyUp QPC。长按采样必须先从 Down 开始读取桌面像素，
     * 不能为了等松键而把“持续按住”的时间排除在呈现观测之外。
     */
    private static long TryReadNativeKeyboardUpQpc(
        string path,
        long markerLength,
        string expectedAction,
        long downQpcUs)
    {
        if (String.IsNullOrWhiteSpace(path) || !File.Exists(path)) return 0;
        try
        {
            var content = File.ReadAllText(path);
            if (content.Length <= markerLength) return 0;
            var recent = content.Substring((int)Math.Min(markerLength, content.Length));
            var lines = recent.Split(new[] { '\r', '\n' },
                StringSplitOptions.RemoveEmptyEntries);
            foreach (var line in lines)
            {
                if (!line.Contains("\"event\":\"native_keyboard_message\"") ||
                    !line.Contains("\"action\":\"" + expectedAction + "\"") ||
                    !line.Contains("\"phase\":\"up\""))
                    continue;
                long qpcUs;
                if (TryReadQpcUs(line, out qpcUs) && qpcUs > downQpcUs)
                    return qpcUs;
            }
        }
        catch
        {
            // 原生观察器追加与桌面探针读取可能短暂交叠；下一帧继续尝试。
        }
        return 0;
    }

    private static void SendMouseInput(uint flags)
    {
        var input = new INPUT {
            type = 0,
            union = new INPUTUNION { mouse = new MOUSEINPUT { dwFlags = flags } }
        };
        if (SendInput(1, new[] { input }, Marshal.SizeOf(typeof(INPUT))) != 1)
            throw new InvalidOperationException("SendInput 未能将鼠标输入写入前台 Windows 输入队列。");
    }

    private static long NowUs()
    {
        return (long)(Stopwatch.GetTimestamp() * 1000000.0 / Stopwatch.Frequency);
    }

    private static void WaitUntil(ref long lastCaptureUs, long captureIntervalUs)
    {
        lastCaptureUs += captureIntervalUs;
        while (NowUs() < lastCaptureUs) Thread.Sleep(1);
        if (NowUs() - lastCaptureUs > captureIntervalUs * 2L) lastCaptureUs = NowUs();
    }

    private static double DifferencePercent(byte[] left, byte[] right)
    {
        if (left == null || right == null || left.Length != right.Length) return 100.0;
        long difference = 0;
        for (var i = 0; i < left.Length; i++) difference += Math.Abs(left[i] - right[i]);
        return difference * 100.0 / (left.Length * 255.0);
    }

    private static double Percentile(List<double> values, double percentile)
    {
        if (values == null || values.Count == 0) return 0.0;
        values.Sort();
        var index = (int)Math.Round((values.Count - 1) * percentile, MidpointRounding.AwayFromZero);
        return values[Math.Max(0, Math.Min(values.Count - 1, index))];
    }
}
'@

# here-string 在 Windows PowerShell 5.1 中保留首/尾换行；Trim 后再交给 C# 编译器，
# 避免将动态源的首行 using 错误映射为外层 PowerShell 的 using 指令。
Add-Type -TypeDefinition $nativeSource.Trim()

if ($ValidateOnly) {
  # 编译门禁不触碰窗口或键盘；CI/开发机可先验证 Win32 采集器是否可加载。
  Write-Output 'PLAYER_DESKTOP_PIXEL_PROBE validate=passed capture=Win32GetDC anonymousGrid=24x14'
  exit 0
}

if (-not $Output) {
  $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
  $Output = Join-Path $PSScriptRoot "..\.local\qa\desktop-pixel-probe\$timestamp"
}
$Output = [System.IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) {
  throw "输出目录已存在，拒绝覆盖既有证据：$Output"
}
New-Item -ItemType Directory -Path $Output -Force | Out-Null

$resolvedVirtualKey = if ($VirtualKey -gt 0 -and $Action -in @(
    'forward', 'backward', 'manualForward', 'manualBackward',
    'manualLongForward', 'manualLongBackward')) {
  # 真实 PlayerPage QA 可从 ready.json 传入用户当前配置的 J/L/箭头等 VK；
  # 未提供时保留专用默认 J/L，避免改变旧的 Texture 对照合同。
  $VirtualKey
} else { switch ($Action) {
  'forward' { 0x4C } # L：默认播放器短按/长按前进
  'backward' { 0x4A } # J：默认播放器短按/长按后退
  'manualForward' { 0x4C } # L：只等待真实实体按键，不由工具注入。
  'manualBackward' { 0x4A } # J：只等待真实实体按键，不由工具注入。
  'manualLongForward' { 0x4C } # L：只等待真实长按，不由工具注入。
  'manualLongBackward' { 0x4A } # J：只等待真实长按，不由工具注入。
  'playPause' { 0x20 }
  'fullscreen' { 0x0D } # Enter：专用 QA 页的全屏快速开关
  'playerFullscreen' { 0x0D } # Enter：正式 PlayerPage 的全屏快捷键
  'click' { 0 }
  'progressDrag' { 0 }
  'custom' {
    if ($VirtualKey -le 0) { throw 'custom 动作必须显式给出 -VirtualKey。' }
    $VirtualKey
  }
} }

$report = [DesktopPixelProbe]::Run(
  $WindowTitle,
  $ProcessId,
  $resolvedVirtualKey,
  ($KeyboardInjectionMode -eq 'virtualKey'),
  ($Action -in @('manualForward', 'manualBackward', 'manualLongForward', 'manualLongBackward')),
  ($Action -in @('manualLongForward', 'manualLongBackward')),
  $ManualLongHoldMinimumMilliseconds,
  ($Action -eq 'click'),
  ($Action -eq 'progressDrag'),
  $PreparePlayerKeyboardFocus.IsPresent,
  $Samples,
  $HoldMilliseconds,
  $ProgressDragStartFraction,
  $ProgressDragEndFraction,
  $ProgressDragBottomInsetPixels,
  $ProgressDragDurationMilliseconds,
  $ExpectedInputEvidencePath,
  $NativeKeyboardEvidencePath,
  $ManualInputTimeoutMilliseconds,
  $FrameRate,
  $PerSampleTimeoutMilliseconds,
  $SettleMilliseconds,
  $PixelChangeThresholdPercent,
  $MinimumEffectiveCaptureFps,
  $RequireStaticBaseline,
  ($Action -in @('fullscreen', 'playerFullscreen')),
  $PixelSamplingMode
)

$json = $report | ConvertTo-Json -Depth 8 -Compress
$reportPath = Join-Path $Output 'desktop-pixel-report.json'
[System.IO.File]::WriteAllText($reportPath, $json, [System.Text.UTF8Encoding]::new($false))

$summary = [ordered]@{
  evidence = $report.evidence
  inputMode = $report.inputMode
  manualLongHoldMinimumMilliseconds = $report.manualLongHoldMinimumMilliseconds
  windowDpi = $report.windowDpi
  requestedCaptureFps = $report.requestedCaptureFps
  effectiveCaptureFps = $report.effectiveCaptureFps
  captureRatePassed = $report.captureRatePassed
  captureReadFailures = $report.captureReadFailures
  successfulSamples = $report.successfulSamples
  timedOutSamples = $report.timedOutSamples
  p50InputDownToPixelMs = $report.p50InputDownToPixelMs
  p95InputDownToPixelMs = $report.p95InputDownToPixelMs
  p50InputUpToPixelMs = $report.p50InputUpToPixelMs
  p95InputUpToPixelMs = $report.p95InputUpToPixelMs
  p50InputDownToGeometryMs = $report.p50InputDownToGeometryMs
  p95InputDownToGeometryMs = $report.p95InputDownToGeometryMs
  actionEvidence = @($report.actions | ForEach-Object resultEvidence | Select-Object -Unique)
  manualHoldDurationsMs = @($report.actions | ForEach-Object physicalKeyHoldDurationMs)
  manualHoldSatisfied = @($report.actions | ForEach-Object manualHoldSatisfied)
  longestUnchangedRunMs = $report.longestUnchangedRunMs
  geometryChanges = $report.geometryChanges
  output = $reportPath
}
$summaryJson = $summary | ConvertTo-Json -Depth 4 -Compress
[System.IO.File]::WriteAllText(
  (Join-Path $Output 'desktop-pixel-summary.json'),
  $summaryJson,
  [System.Text.UTF8Encoding]::new($false)
)
Write-Output "PLAYER_DESKTOP_PIXEL_PROBE $summaryJson"

if (-not $report.captureRatePassed) {
  throw "桌面采样实际仅 $($report.effectiveCaptureFps) fps，低于 $MinimumEffectiveCaptureFps fps；该结果不能作为高刷新率体验结论。"
}
if ($report.successfulSamples -ne $Samples) {
  throw "只有 $($report.successfulSamples)/$Samples 次观察到持久桌面像素变化；请保持暂停基线、确认窗口未遮挡并保留报告。"
}
