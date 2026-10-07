#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""为旧版 dxvk / d9vk 源码补齐新工具链所需的显式头文件。

旧代码依赖标准库头之间的“传递包含”，新版 libstdc++ 不再传递，于是报
'std::exchange' / 'uint32_t' / 'std::ostream' 未声明；另外 mingw-w64 >= 9 的
 d3d11.h 已经自带 D3D11_FORMAT_SUPPORT2，会与源码里的手工复刻冲突。

本脚本只做最小、可校验的插入，不删除任何内容，每步都断言命中次数与文件完整性。
"""
import io
import os
import re
import sys


def read(p):
    return io.open(p, encoding='utf-8').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8').write(s)


def insert_include(path, inc, sniff=None):
    """把 #include <inc> 插到 #pragma once 之后（否则第一条 #include 之后）。"""
    if not os.path.exists(path):
        return path + ': 跳过（文件不存在）'
    s = read(path)
    if re.search(r'#include\s*<' + re.escape(inc) + r'>', s):
        return path + ': 已有 <' + inc + '>'
    if sniff and not re.search(sniff, s):
        return path + ': 用不到 <' + inc + '>'
    m = re.search(r'^#pragma once[^\n]*\n', s, re.M)
    if m:
        pos = m.end()
        head = s[:pos]
    else:
        m2 = re.search(r'^#include[^\n]*\n', s, re.M)
        if m2:
            pos = m2.end()
            head = s[:pos]
        else:
            pos = 0
            head = ''
    s2 = head + '#include <' + inc + '>\n' + s[pos:]          # 关键：必须保留尾部
    assert s2.count('<' + inc + '>') == 1
    assert s2.count('\n') == s.count('\n') + 1, path          # 只多一行
    write(path, s2)
    return path + ': 新增 <' + inc + '>'


# ---- 1) 已知的显式头文件补充 ----
FIXES = [
    ('src/util/util_bit.h',        'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
    ('src/util/util_vector.h',     'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
    ('src/util/util_matrix.h',     'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
    ('src/util/config/config.h',   'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
    ('src/dxvk/dxvk_buffer.h',     'utility',  r'\bstd::exchange\b'),
    ('src/util/rc/util_rc_ptr.h',  'ostream',  r'\bstd::ostream\b'),
    ('src/util/util_enum.h',       'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
    ('src/util/util_flags.h',      'cstdint',  r'\buint(?:8|16|32|64)_t\b'),
]


def fix_exchange_users():
    """扫全树：用 std::exchange 但没有 <utility> 的文件。"""
    out = []
    for root, _, files in os.walk('src'):
        for f in files:
            if not f.endswith(('.cpp', '.h')):
                continue
            p = os.path.join(root, f)
            try:
                s = read(p)
            except Exception:
                continue
            if 'std::exchange' in s and '#include <utility>' not in s:
                out.append(insert_include(p, 'utility'))
    return out


def fix_format_support2():
    """mingw-w64 >= 9 已提供 D3D11_FORMAT_SUPPORT2，跳过源码里的复刻定义。"""
    p = 'src/d3d11/d3d11_include.h'
    if not os.path.exists(p):
        return p + ': 跳过（文件不存在）'
    s = read(p)
    if '__MINGW64_VERSION_MAJOR < 9' in s or 'MINGW64_VERSION_MAJOR < 9' in s:
        return p + ': 已有守卫'
    old = '#ifndef _MSC_VER\ntypedef enum D3D11_FORMAT_SUPPORT2 {'
    if s.count(old) != 1:
        return p + ': 跳过（模式不匹配）'
    s = s.replace(old, '#ifndef _MSC_VER\n'
                        '// mingw-w64 >= 9 provides this in d3d11.h\n'
                        '#if !defined(__MINGW64_VERSION_MAJOR) || __MINGW64_VERSION_MAJOR < 9\n'
                        'typedef enum D3D11_FORMAT_SUPPORT2 {', 1)
    tail = '} D3D11_FORMAT_SUPPORT2;\n'
    i = s.index(tail)
    s = s[:i] + tail + '#endif // __MINGW64_VERSION_MAJOR < 9\n' + s[i + len(tail):]
    write(p, s)
    return p + ': 新增 mingw-w64 >= 9 守卫'


if __name__ == '__main__':
    print('=== 头文件修复 ===')
    for path, inc, sniff in FIXES:
        print(' ', insert_include(path, inc, sniff))
    for line in fix_exchange_users():
        print(' ', line)
    print(' ', fix_format_support2())
    print('完成')
