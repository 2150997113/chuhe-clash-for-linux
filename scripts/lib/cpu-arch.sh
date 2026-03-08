#!/bin/bash
# CPU 架构检测库

# 获取 CPU 架构（设置全局变量 CPU_ARCH）
get_cpu_arch() {
    local arch=""

    # 尝试多种方式获取架构
    if command -v uname >/dev/null 2>&1; then
        arch=$(uname -m 2>/dev/null)
    fi

    if [ -z "$arch" ] && command -v arch >/dev/null 2>&1; then
        arch=$(arch 2>/dev/null)
    fi

    # dpkg 架构（Debian/Ubuntu）
    if [ -z "$arch" ] && command -v dpkg-architecture >/dev/null 2>&1; then
        arch=$(dpkg-architecture -qDEB_HOST_ARCH_CPU 2>/dev/null || dpkg-architecture -qDEB_BUILD_ARCH_CPU 2>/dev/null || true)
    fi

    if [ -n "$arch" ]; then
        CPU_ARCH="$arch"
        export CPU_ARCH
        return 0
    fi

    return 1
}
