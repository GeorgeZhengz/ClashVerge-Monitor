# Clash Verge 稳定配置包 & 监控工具

这个工具包包含了一套经过优化的 Clash Verge 配置文件，以及一个自动监控和重启 Clash 的托盘程序。

## 包含内容

1.  **stable-config.yaml**: 
    *   优化的分流规则（去广告、自动选择最快节点、故障转移）。
    *   高频健康检查（每分钟），防止长时间断连。
    *   智能 DNS 配置，防止 DNS 污染。
2.  **TrayMonitor.ps1**: 
    *   系统托盘监控图标。
    *   实时检测 Google 连接状态。
    *   **智能重启**: 连续失败 3 次自动重启 Clash 应用。
    *   **断网检测**: 区分物理断网和代理故障，避免误重启。
3.  **Setup.bat**: 
    *   自动安装脚本，解决 PowerShell 权限和编码问题。
4.  **Remove.bat**:
    *   一键卸载脚本，自动停止监控、删除开机自启和配置文件。

## 如何安装

1.  解压本文件夹到任意位置（建议放在不会轻易移动的地方，如 `D:\Tools\ClashMonitor`）。
2.  双击运行 **`Setup.bat`**。
    *   *注意：为了兼容性，安装脚本界面已改为英文。*
3.  脚本会自动执行以下操作：
    *   将 `stable-config.yaml` 复制到你的 Clash Verge 配置目录。
    *   创建开机自启快捷方式，以便每次开机自动运行监控程序。
4.  安装完成后，请打开 Clash Verge Rev：
    *   进入 **Profiles (配置)** 界面。
    *   右键点击空白处或点击刷新按钮。
    *   选择新出现的 `stable-config` 并激活。

## 如何卸载

1.  双击运行 **`Remove.bat`**。
2.  脚本会自动：
    *   停止正在运行的监控程序。
    *   删除开机自启快捷方式。
    *   删除 Clash Verge 中的 `stable-config.yaml` 配置文件。
3.  卸载完成后，请在 Clash Verge 中切换回其他配置文件。

## 使用说明

*   **托盘图标**:
    *   🟢 **绿色圆点**: 连接正常。
    *   🔴 **红色圆点**: 连接失败（正在重试）。
    *   🟠 **橙色圆点**: 物理网络中断（请检查网线/Wi-Fi）。
    *   🟡 **黄色 R**: 正在重启 Clash 应用。
*   **右键菜单**:
    *   **Enable Auto Restart**: 开启/关闭 "自动重启" 功能。
    *   **Start on Boot**: 开启/关闭 "开机自启" 功能。
    *   **Exit Monitor**: 退出监控程序。
*   **双击图标**: 尝试打开 Clash Verge 主界面。

## 致谢与声明

本配置集成了以下开源项目的免费节点订阅，特此感谢：

1.  **Pawdroid**: [https://github.com/Pawdroid/Free-servers](https://github.com/Pawdroid/Free-servers)
2.  **二猫子 (Ermaozi)**: [https://github.com/ermaozi/get_subscribe](https://github.com/ermaozi/get_subscribe)
3.  **Anaer**: [https://github.com/anaer/Sub](https://github.com/anaer/Sub)

*注：免费节点稳定性可能不如付费节点，建议作为备用或测试使用。*

## 注意事项

*   如果你的 Clash Verge 安装路径不是默认路径，监控程序可能会提示找不到路径，请确保 Clash Verge 正在运行，或者手动修改 `TrayMonitor.ps1` 中的路径。
*   本程序依赖 PowerShell，Windows 10/11 系统自带。
