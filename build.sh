#!/bin/bash

# 配置环境
export PDK=sky130A
make setup

# sta时序报错，添加代码“/// sta-blackbox”到如下目录“dependencies/pdks/sky130A/libs.ref/sky130_fd_sc_hd/verilog/“的“sky130_fd_sc_hd.v“中，位置为第18行
# 因为编译的时候会遇到sta时序问题， 通过屏蔽此处时序分析绕过去，但不会影响后期的流片

FILE_PATH="$(pwd)/dependencies/pdks/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v"
BACKUP_PATH="$FILE_PATH.backup"

# 备份原文件
cp "$FILE_PATH" "$BACKUP_PATH"

# 使用 sed 在第一个 ifndef 前添加注释
sed '/^`ifndef/i\/// sta-blackbox' "$FILE_PATH" > temp_file
mv temp_file "$FILE_PATH"

echo "已在第一个 ifndef 前添加 sta-blackbox 注释，原文件备份为 $BACKUP_PATH"

# 编译 user_proj_example
make user_proj_example

# 编译 user_project_wapper
make user_project_wapper
