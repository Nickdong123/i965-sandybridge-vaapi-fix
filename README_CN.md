# Intel Sandy Bridge (HD 3000 / Gen6) Chromium & Edge VA-API 硬件解码修复补丁

[![Build Status](https://github.com/Nickdong123/i965-sandybridge-vaapi-fix/actions/workflows/build.yml/badge.svg)](https://github.com/Nickdong123/i965-sandybridge-vaapi-fix/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Linux%20x86__64-lightgrey.svg)]()
[![Hardware](https://img.shields.io/badge/Intel%20GPU-Sandy%20Bridge%20(Gen6)-orange.svg)]()

[English](README.md) | [中文说明](README_CN.md)

本仓库提供针对 Intel 第二代酷睿（**Sandy Bridge / Intel HD Graphics 3000 & 2000 / Gen6 GT2**）显卡的 VA-API 驱动修复补丁，彻底解决现代化 Chromium 内核浏览器（**Microsoft Edge、Google Chrome、Chromium、Brave**）在 Linux 下播放 H.264 视频时无法开启硬件解码、强制降级为 CPU 软解的问题。

已在经典神机 **ThinkPad X220**（Core i5-2520M / HD Graphics 3000，Linux Mint 22 / Ubuntu 24.04 LTS 底包，Microsoft Edge 157）上实机实测验证。

---

## 🚀 实测性能对比与收益

使用标准 Big Buck Bunny H.264 测试流（120 秒连续播放）：

| 视频规格 | 解码模式 | CPU 平均占用率 | 丢帧率 | 风扇转速与发热 | 体验结论 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **720p 30fps (H.264)** | 修复前（CPU 软解 / FFmpeg） | 46.3% | 0.0% | 中等 | 基准表现 |
| **720p 30fps (H.264)** | **修复后（VA-API 硬解）** | **28.1% (-39.3%)** | **0.0%** | 静音低温 | **流畅省电** |
| **1080p 30fps (H.264)** | 修复前（CPU 软解 / FFmpeg） | 78.1% | 4.7%（明显丢帧）| 4200 RPM（高速呼啸）| 卡顿、偶发音画不同步 |
| **1080p 30fps (H.264)** | **修复后（VA-API 硬解）** | **46.1% (-41.0%)** | **0.0%（零丢帧）** | 3100 RPM（平稳静音）| **丝滑稳定 60 帧** |

- **CPU 负载骤降 40%**：原本 1080p 几乎吃满双核 CPU，现在稳定在 46% 左右。
- **1080p 彻底告别丢帧**：从 4.7% 丢帧率降为 **0 丢帧**。
- **发热显著降低**：整机降温约 8°C，风扇不再咆哮，大幅延长老笔记本续航。

---

## 🔍 问题根因深度剖析

现代 Chromium（120+ 及 Edge）重构了 Linux 平台的视频解码渲染管线，全面强制要求基于 DMA-BUF 的纹理共享机制（`AcceleratedVideoDecodeLinuxGL`），并通过 `EGL_EXT_image_dma_buf_import` 与 DRM Prime fd（`vaExportSurfaceHandle`）直接将硬解显存句柄导入 OpenGL 纹理。

在 Sandy Bridge（Gen6 架构）上，官方已归档停更的 `intel-vaapi-driver 2.4.1` 存在三大阻塞点：
1. **DRM Prime 导出缺失**：官方驱动仅在 Gen7+（Ivy Bridge、Haswell）上暴露了导出 API，Gen6 调用 `vaExportSurfaceHandle` 直接返回不支持错误。
2. **VPP 颜色空间转换属性缺失**：Chromium 在初始化管线时会查询 `VASurfaceAttribPixelFormat`，要求驱动支持 `BGRA` 和 `ARGB` 的 VPP 变换。Gen6 驱动默认未注册这两种格式的查询响应。
3. **Gen6 流水线标志位错配**：在 `i965_post_processing.c` 中，初始化流水线参数时误用了 `I_I` 标志而非 Sandy Bridge 专属的 `I_SI` 标志，导致 VPP 色彩转换管线握手失败。

任何一步失败，Chromium 就会默默判定 GPU 不可用并报错退化为 CPU 软解（`FFmpegVideoDecoder`）。

---

## 💡 解决方案

本仓库整合了统一的补丁 `0001-sandybridge-edge-vaapi-h264-vpp-export-fix.patch`：
- **完整实现 Gen6 的 `vaExportSurfaceHandle`**：计算准确的平铺（Tiling）行间距与显存偏移，正确输出 DRM Prime fd。
- **补全 VPP BGRA/ARGB 属性**：让 Gen6 完美通过 Chromium 的管线协商。
- **修正流水线标志位**：确保色空间转换及纹理绑定正常。
- **纯用户态隔离部署**：自动将修补后的驱动编译到独立目录，通过启动器环境变量载入，**绝对不覆盖系统原本的驱动包**，绝不影响系统稳定性，可随时彻底回滚。

---

## 🛠️ 快速上手

### 1. 安装编译依赖

Debian / Ubuntu / Linux Mint：
```bash
sudo apt update
sudo apt install -y build-essential pkg-config libva-dev libdrm-dev libx11-dev libgl1-mesa-dev vainfo
```

Fedora：
```bash
sudo dnf install -y gcc make pkgconf libva-devel libdrm-devel libX11-devel mesa-libGL-devel libva-utils
```

Arch Linux：
```bash
sudo pacman -S --needed base-devel libva libdrm libx11 mesa libva-utils
```

### 2. 克隆本仓库并一键编译

```bash
git clone https://github.com/Nickdong123/i965-sandybridge-vaapi-fix.git
cd i965-sandybridge-vaapi-fix

# 运行自动化编译脚本（自动拉取官方 2.4.1 源码、打补丁并编译）
chmod +x scripts/*.sh
./scripts/build.sh
```

### 3. 一键安装浏览器快捷方式

```bash
./scripts/install.sh
```

`install.sh` 会自动检测系统已安装的浏览器（`Microsoft Edge`、`Google Chrome`、`Chromium`、`Brave`），并在 `~/.local/share/applications/` 自动生成专属桌面启动器。

安装完成后，直接在系统应用菜单中点击带有 **"(VA-API Patched)"** 后缀的浏览器启动即可！

---

## 🖥️ 命令行手动启动方式

如果不希望使用桌面启动器，可以直接在终端中指定环境变量与参数启动：

```bash
export DRIVER_DIR="$(pwd)/out"

# 启动 Microsoft Edge
env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH="$DRIVER_DIR" \
    /opt/microsoft/msedge/msedge \
    --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --enable-zero-copy

# 启动 Google Chrome
env LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH="$DRIVER_DIR" \
    /opt/google/chrome/google-chrome \
    --enable-features=AcceleratedVideoDecodeLinuxGL,VaapiIgnoreDriverChecks \
    --ignore-gpu-blocklist \
    --enable-gpu-rasterization \
    --enable-zero-copy
```

---

## ✅ 验证是否成功生效

### 1. `vainfo` 检查
```bash
LIBVA_DRIVER_NAME=i965 LIBVA_DRIVERS_PATH=./out vainfo
```
确认终端输出中包含：
```text
va_openDriver() returns 0
VAProfileH264Main               :	VAEntrypointVLD
VAProfileH264High               :	VAEntrypointVLD
```

### 2. 浏览器内部验证
1. 打开打好补丁的浏览器；
2. 访问 `edge://gpu` 或 `chrome://gpu`，确认 **Video Decode** 显示为 `Hardware accelerated`；
3. 打开 Bilibili 或 YouTube 播放一段 1080p H.264 视频；
4. 访问 `edge://media-internals`（或按 F12 打开 DevTools -> Media 面板）：
   - 确认 **kVideoDecoderName** 为 **`VaapiVideoDecoder`**（而非 `FFmpegVideoDecoder`）；
5. 终端运行 `intel_gpu_top`，可观察到显卡 Video / Render 引擎正在实时工作，而 CPU 占用平稳低温。

---

## 🧹 卸载与无痕回滚

如果需要移除补丁桌面启动器：
```bash
./scripts/uninstall.sh
```
所有生成的启动器将被清除，系统本身无任何残留变更。

---

## 📜 开源许可与致谢

- 本补丁与脚本采用 [MIT 许可证](LICENSE) 开源。
- 基础驱动代码属于 Intel 官方开源项目 `intel-vaapi-driver`（MIT 协议）。
- 感谢开源社区及 Luke Esau 早期对表面句柄导出的探索贡献。
