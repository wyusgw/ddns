# DDNS - 动态 DNS 更新脚本

## 概述

DDNGG 是一个简单的脚本，用于自动更新您的动态 DNS（DDNS）记录。它帮助确保即使您的 IP 地址发生变化，您的域名始终指向正确的 IP。

该项目提供了一个可以在 Linux 服务器上运行的脚本，保持您的 DNS 记录与公共 IP 地址同步更新。

## 特性

- 自动更新 DNS 记录。
- 支持自定义 DNS 提供商。
- 使用简单，快速配置。
- ✨ **新增**：支持为每个域名设置自定义名称标识，改进 Telegram 通知显示
- ✨ **新增**：Telegram 通知新增时间戳和结构化格式

## 安装方法

要使用此脚本，请按照以下步骤进行操作：

### 系统要求
- 一个基于 Linux 的系统（Ubuntu、Debian、CentOS 等）
- 安装了 `wget`
- 一个支持动态 DNS 更新的域名（DNS 提供商）

### 食用方法

1. 下载并执行脚本

```bash
bash <(wget -qO- https://raw.githubusercontent.com/wyusgw/ddns/refs/heads/main/ddns.sh)
