#!/bin/bash
# 交叉编译 agent 到常见 Linux 架构。产物命名 macos-monitor-agent-linux-<arch>.
set -euo pipefail
cd "$(dirname "$0")"

export CGO_ENABLED=0
LDFLAGS="-s -w"  # strip symbols; binary 从 ~5MB 压到 ~2MB

for arch in amd64 arm64; do
    out="macos-monitor-agent-linux-${arch}"
    echo "==> building ${out}"
    GOOS=linux GOARCH=${arch} go build -ldflags="${LDFLAGS}" -o "${out}" .
    ls -lh "${out}"
done

echo ""
echo "✓ done. scp to VPS:"
echo "  scp macos-monitor-agent-linux-amd64 user@host:~/macos-monitor-agent"
echo "  ssh user@host 'chmod +x ~/macos-monitor-agent'"
