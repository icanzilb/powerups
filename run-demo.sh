#!/bin/zsh
swift build -c release
./.build/release/powerups etc/files/root.xml --variables etc/files/global-variables.json --includesFolder etc/files
