# Intel Sandy Bridge (HD 3000 / Gen6) Chromium & Edge VA-API 硬件解码修复补丁

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20x86__64-lightgrey.svg)]()
[![Hardware](https://img.shields.io/badge/Intel%20GPU-Sandy%20Bridge%20(Gen6)-orange.svg)]()
[![Release](https://img.shields.io/github/v/release/Nickdong123/i965-sandybridge-vaapi-fix)](https://github.com/Nickdong123/i965-sandybridge-vaapi-fix/releases)

[English](README.md) | [中文说明](README_CN.md)

本仓库提供针对 Intel 第二代酷睿（**Sandy Bridge / Intel HD Graphics 3000 & 2000 / Gen6 GT2**）显卡的 VA-API 驱动修复补丁，彻底解决现代化 Chromium 内核浏览器（**Microsoft Edge、Google Chrome、Chromium、Brave**）在 Linux 下播放 H.264 视频时无法开启硬件解码、强制降级为 CPU 软解的问题。

已在经典神机 **ThinkPad X220**（Core i5-2520M / HD Graphics 3000，Linux Mint 22 / Ubuntu 24.04 LTS 底包，Microsoft Edge 157）上实机实测验证。

---

## 🎯 核心焦点：如何识别“假性硬解成功”？

在排查和测试老旧硬件时，最容易遇到的典型误区是：
> **`edge://gpu` 显示 `Video Decode: Hardware accelerated`，但实际播放视频时仍然在用 CPU 软解！**

* **修复前（假性硬解）**：`edge://gpu` 虽显示硬件加速，但 `edge://media-internals` 显示 VA-API 首次解码即报错，底层抛出 `"video decoder fallback after initial decode error"`，随后**悄悄降级为 FFmpeg 软解**。
* **修复后（真正硬解）**：实测 1280×720 / 1920×1080、30 FPS、H.264 视频，**持续播放数分钟后仍稳定显示 `VaapiVideoDecoder` 和 `kIsPlatformVideoDecoder: true`**，零丢帧、零回退。

本项目不仅提供开箱即用的一键修复补丁，更提供一套完整严谨的“真假硬解识别与对照验证体系”。

---

## 🚀 实测性能对比与双场景分析

测试采用标准 Big Buck Bunny H.264 测试流（120 秒连续播放）。

### 1. 独立纯净回放模式（无后台高干扰）
*直接采样浏览器视频解码核心进程与纯净系统表现：*

| 视频规格 | 解码模式 | 单核 CPU 峰值 | 整机 CPU 总负载 | 丢帧情况 | 运行状态 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **720p 30fps (H.264)** | 软解（FFmpeg/OpenH264） | 46.3% | 11.6% | 0 | 基准软解表现 |
| **720p 30fps (H.264)** | **VA-API 补丁硬解** | **28.1% (-39.3%)** | **7.0%** | **0** | **轻载低温** |
| **1080p 30fps (H.264)** | 软解（FFmpeg/OpenH264） | 78.1% | 19.5% | 偶发卡顿 | CPU 高负荷发热 |
| **1080p 30fps (H.264)** | **VA-API 补丁硬解** | **18.0% (-76.9%)** | **4.5%** | **0（零丢帧）** | **丝滑 60 帧，整机静音** |

> **核心收益**：在独立回放场景下，VA-API 硬件解码将解码核心占用的单核 CPU 负载从 **78.1% 暴降至 18.0%（降幅达 76.9%）**，整机功耗与发热得到根本性改善。

### 2. 重度多任务极限并发模式（真实生产力工况）
*测试环境：后台同时并发运行多个本地 AI 编码智能体（Claude / Codex / agy）及 Firefox 视频流：*

| 视频规格 | 解码模式 | 整机全局 CPU 占用 | 丢帧率 | 风扇转速与发热 | 体验结论 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1080p 30fps** | 软解（FFmpeg） | 78.1% | 4.7%（严重丢帧） | 4200 RPM（高速呼啸）| 画面卡顿、偶发音画脱节 |
| **1080p 30fps** | **VA-API 补丁硬解** | **46.1% (-41.0%)**| **0.0%（零丢帧）** | 3100 RPM（平稳静音）| **硬解稳如磐石，彻底消除卡顿** |

即便在 CPU 被后台任务大幅消耗的高压力场景下，硬件解码将计算完全移交给 GPU 专有电路，从根本上杜绝了因 CPU 资源竞争导致的视频跳帧与卡死。

---

## 🔍 问题根因深度剖析

现代 Chromium（120+ 及 Edge）全面采用基于 DMA-BUF 的纹理共享机制（`AcceleratedVideoDecodeLinuxGL`），并通过 `EGL_EXT_image_dma_buf_import` 与 DRM Prime fd（`vaExportSurfaceHandle`）直接将硬解显存句柄导入 OpenGL 纹理。

在 Sandy Bridge（Gen6 架构）上，官方 `intel-vaapi-driver 2.4.1` 存在三大阻塞点：
1. **DRM Prime 导出缺失**：官方驱动仅在 Gen7+（Ivy Bridge、Haswell）上暴露了导出 API，Gen6 调用 `vaExportSurfaceHandle` 直接失败。
2. **VPP 颜色空间转换属性缺失**：Chromium 在初始化管线时会查询 `VASurfaceAttribPixelFormat`，要求驱动支持 `BGRA` 和 `ARGB` 的 VPP 变换。Gen6 驱动默认未注册这两种格式的查询响应。
3. **Gen6 流水线标志位错配**：在 `i965_post_processing.c` 中，初始化流水线参数时误用了 `I_I` 标志而非 Sandy Bridge 专属的 `I_SI` 标志，导致 VPP 色彩转换管线握手失败。

任何一步失败，Chromium 就会默默判定 GPU 不可用并报错退化为 CPU 软解（`FFmpegVideoDecoder`）。

---

## 💡 解决方案

本仓库整合了统一的补丁 `0001-sandybridge-edge-vaapi-h264-vpp-export-fix.patch`：
- **完整实现 Gen6 的 `vaExportSurfaceHandle`**：计算准确的平铺（Tiling）行间距与显存偏移，正确输出 DRM Prime fd。
- **补全 VPP BGRA/ARGB 属性**：让 Gen6 完美通过 Chromium 的管线协商。
- **修正流水线标志位**：确保色空间转换及纹理绑定正常。
- **纯用户态安全部署**：编译出的 `i965_drv_video.so` 存放在 `~/.local/lib/dri/`，**不覆盖系统原本的驱动包**，绝不影响系统全局稳定性。

---

## 🛠️ 快速上手

### 方式 A：直接下载预编译包（推荐，最快）
从 [Releases 页面](https://github.com/Nickdong123/i965-sandybridge-vaapi-fix/releases) 下载 `i965-vaapi-driver-sandybridge-v1.0.0-x86_64.tar.gz`：
```bash
mkdir -p ~/.local/lib/dri
tar -xzf i965-vaapi-driver-sandybridge-v1.0.0-x86_64.tar.gz -C ~/.local/lib/dri/
```

### 方式 B：源码本地编译
```bash
git clone https://github.com/Nickdong123/i965-sandybridge-vaapi-fix.git
cd i965-sandybridge-vaapi-fix
chmod +x scripts/*.sh
./scripts/build.sh
./scripts/install.sh
```

---

## 🖥️ 命令行手动启动验证

```bash
export LIBVA_DRIVER_NAME=i965
export LIBVA_DRIVERS_PATH="$HOME/.local/lib/dri"

# 启动 Microsoft Edge
/opt/microsoft/msedge/msedge     --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks     --ignore-gpu-blocklist     --enable-gpu-rasterization     --enable-zero-copy

# 启动 Google Chrome
/opt/google/chrome/google-chrome     --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks     --ignore-gpu-blocklist     --enable-gpu-rasterization     --enable-zero-copy
```

---

## ⚙️ 启动参数深度解析

启动命令中各项关键参数的作用如下：

| 参数 / 环境变量 | 作用解析 |
| :--- | :--- |
| `LIBVA_DRIVER_NAME=i965` | 强制指定使用经典开源 i965 显卡驱动，避免系统尝试加载不兼容的 iHD 驱动。 |
| `LIBVA_DRIVERS_PATH=$HOME/.local/lib/dri` | 定向加载位于用户目录的修补驱动共享库，实现免 root、免覆盖系统的安全隔离加载。 |
| `--enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks` | 启用现代 Linux DMA-BUF 纹理共享硬解管线，并跳过 Chromium 对旧版驱动版本的拦截。 |
| `--ignore-gpu-blocklist` | 绕过 Chromium 内置的旧硬件黑名单（Sandy Bridge 于 2011 年发布，默认会被部分特性软拉黑）。 |
| `--enable-gpu-rasterization` | 开启网页 2D 绘图与 CSS 渲染的 GPU 硬件光栅化，减轻 CPU 界面绘制压力。 |
| `--enable-zero-copy` | 开启零拷贝显存直通机制，解码后的显存纹理直接交给合成器，避免在内存与显存之间二次搬运。 |

---

## 🔍 如何验证 VA-API 硬件视频解码是否真正生效

> **重要：** `edge://gpu` 显示 `Video Decode: Hardware accelerated`，并不代表当前播放的视频已经使用硬件解码。建议通过 `edge://media-internals` 验证实际解码器。

### 1. 检查浏览器的硬件加速能力

在 Microsoft Edge 地址栏输入：
```text
edge://gpu
```
找到 **Graphics Feature Status**，重点检查以下项目：

| 项目 | 理想状态 | 作用 |
| :--- | :--- | :--- |
| **Video Decode** | **Hardware accelerated** | 视频硬件解码能力已启用 |
| Compositing | Hardware accelerated | GPU 页面合成 |
| Canvas | Hardware accelerated | Canvas 图形加速 |
| Rasterization | Hardware accelerated | GPU 光栅化 |
| OpenGL | Enabled | OpenGL 功能可用 |
| WebGL | Hardware accelerated | WebGL 图形加速 |

同时可以检查页面中的 **Video Acceleration Information**，确认 H.264 的 Baseline、Main 或 High Profile 解码能力是否存在。

**注意：** 以上结果只代表浏览器识别到了硬件加速能力，并不保证实际播放视频时会使用 GPU 解码。

---

### 2. 确认播放的视频采用 H.264 编码

在 Edge 中打开 YouTube 视频，建议先选择 720P、30 FPS 进行测试。
右键视频画面，选择 **Stats for nerds（详细统计信息）**。
查看 `Codecs`：

| 编码标识 | 视频格式 | Intel HD Graphics 3000 (Sandy Bridge) |
| :--- | :--- | :--- |
| **`avc1`** | **H.264 / AVC** | **✅ 支持硬件解码** |
| `vp09` | VP9 | ❌ 不支持硬件解码 |
| `av01` | AV1 | ❌ 不支持硬件解码 |

对于 Intel Sandy Bridge / HD Graphics 3000，必须确保视频流使用 H.264。
如有必要，可以使用 **enhanced-h264ify** 等浏览器扩展屏蔽 VP9 和 AV1。

---

### 3. 检查实际使用的视频解码器（最关键）

保持视频正常播放，另开一个 Edge 标签页打开：
```text
edge://media-internals
```
在 **Players** 页面：
1. 找到左侧对应视频的播放器记录（通常是 `blob:https://www.youtube.com/...`）；
2. 优先选择状态为 `kPlay` 的播放器；
3. 查看右侧 **Properties** 和 **Events** 中的视频解码信息。

#### 真实截图案例 1：当前播放器属性状态（Properties）
![当前播放器属性状态](docs/images/01_edge_player_properties.png)

**硬件解码成功时，应显示：**
```text
kVideoDecoderName: VaapiVideoDecoder
kIsPlatformVideoDecoder: true
```

#### 真实截图案例 2：初始化事件流水记录（Events）
![初始化事件流水记录](docs/images/02_edge_init_events.png)

通常还会看到：
```text
VideoDecoderPipeline |decoder_| Initialize() successful
Selected VaapiVideoDecoder for video decoding
```
这些记录说明当前播放器选择了 VA-API 视频解码器，并启用了平台硬件解码路径。

**如果实际使用软件解码，则通常显示：**
```text
kVideoDecoderName: FFmpegVideoDecoder
kIsPlatformVideoDecoder: false
```

---

### 4. 特别检查是否发生硬解回退（最核心避坑点）

这是本项目需要重点解决的问题。

在未修复的旧版 i965 驱动环境中，Chromium / Edge 可能先成功初始化硬件解码器：
```text
00:00:00.247
kVideoDecoderName: VaapiVideoDecoder
kIsPlatformVideoDecoder: true
```
但随后因 `vaExportSurfaceHandle` 失败而抛出：
```text
video decoder fallback after initial decode error.
```
并切换到：
```text
kVideoDecoderName: FFmpegVideoDecoder
kIsPlatformVideoDecoder: false
```
这种情况说明 **VA-API 初始化成功，但实际视频解码失败，浏览器已经回退到 CPU 软件解码**。

因此，不能仅凭第一次出现的 `VaapiVideoDecoder` 就判断修复成功。

#### 真实截图案例 3：持续播放数分钟后的解码状态（稳态无回退）
![持续播放数分钟后的解码状态](docs/images/03_edge_continuous_playback.png)

建议连续播放视频至少 1～5 分钟，期间或播放结束前再次检查：
* 当前 `kVideoDecoderName` 仍为 `VaapiVideoDecoder`；
* 当前 `kIsPlatformVideoDecoder` 仍为 `true`；
* 事件记录中**没有**后续回退到 `FFmpegVideoDecoder`；
* 视频正常播放，没有持续黑屏、花屏或明显解码异常。

如果播放过程中解码器重新初始化，应检查重新初始化后的最终状态。

---

### 5. 不要误判 FFmpegAudioDecoder

在 `edge://media-internals` 中还可能看到：
```text
kAudioDecoderName: FFmpegAudioDecoder
kIsPlatformAudioDecoder: false
```
**这是音频解码信息，不代表视频硬件解码失败。**
YouTube 的 AAC 等音频流可以使用 FFmpeg 软件解码，同时 H.264 视频流仍然由 VA-API 硬件解码。
判断视频是否硬解，只需重点查看：
* `kVideoDecoderName`
* `kIsPlatformVideoDecoder`

不要把 `kAudioDecoderName` 与 `kVideoDecoderName` 混淆。

---

### 6. 修复前后验证标准对照表

| 检查项 | 修复前典型表现 | 修复成功后的表现 |
| :--- | :--- | :--- |
| `edge://gpu` Video Decode | Hardware accelerated | Hardware accelerated |
| 视频编码格式 | H.264 (`avc1`) | H.264 (`avc1`) |
| 解码器初始化 | VA-API 成功 | VA-API 成功 |
| 首次解码 | 报错失败（Buffer 导出异常） | 正常通过 |
| 解码器回退现象 | 发生回退（Fallback to FFmpeg） | **无任何回退** |
| 最终 Video Decoder | `FFmpegVideoDecoder` (软解) | **`VaapiVideoDecoder` (硬解)** |
| Platform Video Decoder | `false` | **`true`** |
| 硬件芯片工作负载 (`intel_gpu_top`) | Video 引擎 0.0% | **Video 引擎 20%~40% 活跃** |

**最终判断标准：**
`edge://gpu` 确认硬件解码能力已启用，`edge://media-internals` 确认 H.264 视频实际使用 `VaapiVideoDecoder`，并且持续播放时没有回退到软件解码器。

---

### 7. 可选：验证实际性能收益

硬解恢复后，还可以使用相同的视频、分辨率、帧率和测试时间，对比修复前后的 CPU 使用情况。
建议记录：
- 浏览器整体 CPU 使用率或累计 CPU 时间；
- 视频分辨率和帧率；
- YouTube 详细统计信息中的丢帧数量；
- 是否出现卡顿、花屏或播放异常。

注意，浏览器整体 CPU 开销还包括网页 JavaScript、渲染、图形合成和音频处理。因此，即使硬件视频解码已经生效，CPU 使用率也不一定非常低。

---

**适用范围：** 以上方法主要用于 Microsoft Edge / Chromium 在 Linux 下的 VA-API H.264 视频解码验证。对于 Intel HD Graphics 3000 等旧核显，VP9、AV1 不属于其硬件解码能力范围。

---

## 🧹 卸载与无痕回滚

运行 `./scripts/uninstall.sh` 或删除 `~/.local/lib/dri/i965_drv_video.so` 即可彻底回滚，操作系统原有配置 100% 保持原样。

---

## 📜 开源许可与致谢

- 遵循 [MIT 许可证](LICENSE) 开源。
- 基础驱动属于 Intel 官方开源项目 `intel-vaapi-driver`（MIT 协议）。
- 感谢社区与 Luke Esau 早期对表面句柄导出的探索贡献。
