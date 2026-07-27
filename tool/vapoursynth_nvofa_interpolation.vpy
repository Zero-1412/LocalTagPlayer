"""
把 mpv 提供的 video_in 交给 Local Tag Player 的本机 NVOFA 2× 插帧插件。

插件路径只能由显式环境变量提供；脚本不扫描当前目录、不下载运行时，也不会在
找不到插件时静默退回线性混帧。失败由原生宿主识别并撤销当前会话滤镜。
"""

if not user_data or "|" not in user_data:
    raise RuntimeError("NVOFA plugin path or active D3D11 adapter LUID is missing")
if container_fps <= 0:
    raise RuntimeError("Source FPS is unavailable")

# mpv 的嵌入式 VSScript 运行时不保证 Python 标准库搜索路径完整；这里只使用
# 它必需的 vapoursynth 模块以及显式提供的三个变量，避免依赖 os/fractions。
import vapoursynth as vs

core = vs.core
plugin_path, adapter_luid = user_data.rsplit("|", 1)
if not plugin_path or len(adapter_luid) != 17 or adapter_luid[8] != ":":
    raise RuntimeError("NVOFA active D3D11 adapter LUID is invalid")
core.std.LoadPlugin(path=plugin_path, altsearchpath=True)
source_fps_den = 1000
source_fps_num = int(round(container_fps * source_fps_den))

# VapourSynth 要求 VSVideoInfo 中的帧率已经约分，否则会拒绝滤镜输出。
# 这里不用 Python 标准库，避免嵌入式 VSScript 环境缺少标准库搜索路径。
fps_gcd_left = source_fps_num
fps_gcd_right = source_fps_den
while fps_gcd_right:
    fps_gcd_left, fps_gcd_right = (
        fps_gcd_right,
        fps_gcd_left % fps_gcd_right,
    )
source_fps_num //= fps_gcd_left
source_fps_den //= fps_gcd_left
video_out = core.ltp_nvofa.Interpolate(
    clip=video_in,
    source_fps_num=source_fps_num,
    source_fps_den=source_fps_den,
    adapter_luid=adapter_luid,
)

# mpv 0.40 通过 VSScript R78 的 output index 0 取回节点，不读取同名 Python 变量。
video_out.set_output()
