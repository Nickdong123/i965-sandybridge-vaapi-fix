# Intel Sandy Bridge (HD 3000 / Gen6) Chromium & Edge VA-API 硬件解码修复补丁

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20x86__64-lightgrey.svg)]()
[![Hardware](https://img.shields.io/badge/Intel%20GPU-Sandy%20Bridge%20(Gen6)-orange.svg)]()
[![Release](https://img.shields.io/github/v/release/Nickdong123/i965-sandybridge-vaapi-fix)](https://github.com/Nickdong123/i965-sandybridge-vaapi-fix/releases)

[English](README.md) | [中文说明](README_CN.md)

本仓库提供针对 Intel 第二代酷睿（**Sandy Bridge / Intel HD Graphics 3000 & 2000 / Gen6 GT2**）显卡的 VA-API 驱动修复补丁，彻底解决现代化 Chromium 内核浏览器（**Microsoft Edge、Google Chrome、Chromium、Brave**）在 Linux 下播放 H.264 视频时无法开启硬件解码、强制降级为 CPU 软解的问题。

已在经典神机 **ThinkPad X220**（Core i5-2520M / HD Graphics 3000，Linux Mint 22 / Ubuntu 24.04 LTS 底包，Microsoft Edge 157）上实机实测验证。

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
/opt/microsoft/msedge/msedge \
    --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --enable-zero-copy

# 启动 Google Chrome
/opt/google/chrome/google-chrome \
    --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --enable-zero-copy
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

## ✅ 如何准确验证硬件解码已真实生效？

### ⚠️ 重要避坑警示：为什么不能只看 `edge://gpu`？
很多用户会查看 `edge://gpu` 中的 **Video Decode: Hardware accelerated**，并误以为这就是硬解生效的证据。**这是经典误区！**
* **真相**：`edge://gpu` 仅表示浏览器配置“**允许尝试硬件解码**”。在修复之前，该页面就已经是绿色的 `Hardware accelerated`；
* **致命回退**：在未打补丁时，当您真正播放视频时，Chromium 会在底层尝试调用 `vaExportSurfaceHandle`，失败后在后台静默抛出错误：`"video decoder fallback after initial decode error"`，并**偷偷降级回 CPU 软解（FFmpegVideoDecoder）**，此时 `edge://gpu` 依然会显示加速！

---

### 真正的两大权威黄金判定标准：

#### 1. 浏览器内核心态（播放时动态检查）
在 Edge 播放任意 1080p H.264 视频（如 Bilibili 或 YouTube）时：
* **方式 A（直观页面）**：在地址栏输入 `edge://media-internals`，在当前活跃的播放器列表中查看：
  * **`kVideoDecoderName`** 必须是 **`VaapiVideoDecoder`**（若为 `FFmpegVideoDecoder` 则说明退化为软解）；
  * **`kIsPlatformVideoDecoder`** 必须为 **`true`**；
  * 列表中**不得出现**任何 `decoder fallback` 警告。
* **方式 B（开发者工具）**：在播放网页按 `F12` 打开 DevTools -> 切换到 `Media` 面板 -> 点击左侧播放实例 -> 查看 `Decoder Name` 是否为 `VaapiVideoDecoder`。

#### 2. 硬件芯片物理工作负载（底层铁证）
在终端中执行显卡硬件监控工具：
```bash
sudo intel_gpu_top
```
在播放 1080p 视频时观察终端界面：
* **软解状态**：显卡底层的 **`Video`** 引擎占用率为 **0.0%**，而整机 CPU 占用率飙高至 50%~80%，风扇轰鸣；
* **硬解生效状态**：显卡底层的 **`Video`** 引擎会实时出现持续的动态百分比（通常为 **20% ~ 40%**），而 CPU 占用平稳低温，风扇保持静音！

---

## 🧹 卸载与无痕回滚

运行 `./scripts/uninstall.sh` 或删除 `~/.local/lib/dri/i965_drv_video.so` 即可彻底回滚，操作系统原有配置 100% 保持原样。

---

## 📜 开源许可与致谢

- 遵循 [MIT 许可证](LICENSE) 开源。
- 基础驱动属于 Intel 官方开源项目 `intel-vaapi-driver`（MIT 协议）。
- 感谢社区与 Luke Esau 早期对表面句柄导出的探索贡献。
