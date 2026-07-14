<div>

[**English**](README.md)

</div>

# FlClash Fix

[![Android](https://github.com/pingg241/Flclash_fix/actions/workflows/build-android.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-android.yml)
[![Windows](https://github.com/pingg241/Flclash_fix/actions/workflows/build-windows.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-windows.yml)
[![Linux](https://github.com/pingg241/Flclash_fix/actions/workflows/build-linux.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-linux.yml)
[![macOS](https://github.com/pingg241/Flclash_fix/actions/workflows/build-macos.yml/badge.svg)](https://github.com/pingg241/Flclash_fix/actions/workflows/build-macos.yml)
[![License](https://img.shields.io/github/license/pingg241/Flclash_fix?style=flat-square)](LICENSE)

FlClash Fix 是 [FlClash](https://github.com/chen08209/FlClash) 的社区维护修改版，
重点提升可靠性、安全边界、性能和失败处理。支持 Android、Windows、Linux、macOS，
并使用独立维护的[修改版 Meta 内核](https://github.com/pingg241/Clash.Meta)。

本仓库不是 FlClash 或 MetaCubeX 官方发行版。原项目版权、署名及 GPL-3.0
许可证均予以保留。

## 主要修改

- 桌面 IPC 增加双向认证、长度限制、读写超时、背压、断连处理和真实错误传播。
- 配置应用、内核启动、回滚、监听器、DNS、NTP、Geo 更新、TUN 和路由改为事务化生命周期。
- 修复内核命令、代理选择、Profile 切换、关闭连接、退出和平台操作中的“假成功”。
- Android VPN/TUN 使用 operation generation、有界取消和真实 ACK；加强 JNI 异常处理、
  快捷方式、Deep Link、DocumentsProvider 及图标缓存。
- 加固 Windows helper 的调用者认证、进程管理、Debug/Release 隔离和 secure-storage 原生实现。
- Linux/macOS 使用最小权限 TUN helper、认证控制消息、安全 token 文件和严格 FD 所有权。
- 备份、恢复、清库、偏好设置和 WebDAV 密钥保存使用可恢复事务，并防御 ZIP 穿越与压缩炸弹。
- 对下载、HTTP body、事件队列、缓存和并发任务设置明确上限，避免 OOM、永久阻塞和资源泄漏。
- 优化延迟排序、日志和请求懒构建、Provider single-flight，减少重复计算和 O(n²) 路径。
- 分离 Android、Windows、Linux、macOS GitHub Actions，tag 构建全部成功后自动发布 Release 和校验和。

## 截图

桌面端：

<p align="center">
  <img alt="FlClash 桌面端" src="snapshots/desktop.gif">
</p>

移动端：

<p align="center">
  <img alt="FlClash 移动端" src="snapshots/mobile.gif">
</p>

## 功能

- 支持 Android、Windows、Linux、macOS
- Material You、自适应布局和多主题
- 订阅导入、代理组、规则、TUN 模式和系统代理
- WebDAV 同步及本地备份恢复
- 深色模式、流量/日志、连接管理和系统托盘

## 下载

构建产物和正式版本发布在：

<https://github.com/pingg241/Flclash_fix/releases>

未配置私有签名 secrets 时，Android CI 使用仓库中公开的固定签名密钥。该密钥不是
秘密，仅适用于本修改版发布的安装包。

## 构建

初始化修改版内核：

```bash
git submodule update --init --recursive
```

安装 Flutter、Go、Rust 和对应平台 SDK 后运行：

```bash
dart setup.dart android
dart setup.dart windows
dart setup.dart linux
dart setup.dart macos
```

与 CI 一致的检查命令：

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

推送到 `main` 会分别运行各平台 workflow。推送 `v*` tag 后，只有全部平台构建成功，
才会自动创建 GitHub Release 并上传产物及 `SHA256SUMS`。

## 上游项目

- FlClash：<https://github.com/chen08209/FlClash>
- Mihomo：<https://github.com/MetaCubeX/mihomo>
- 修改版 Meta 内核：<https://github.com/pingg241/Clash.Meta>

## 许可证

GPL-3.0，详见 [LICENSE](LICENSE)。应用和内核的修改源码均在上述仓库公开。
