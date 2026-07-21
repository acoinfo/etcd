# etcd-sylixos — etcd 移植 SylixOS

etcd v3.6.13 移植（分布式 KV 存储），纯 Go 实现，基于上游 etcd-io/etcd。

- Go 编译器：https://github.com/acoinfo/go/tree/sylixos-patch_on_go1.25
- 上游仓库：https://github.com/etcd-io/etcd v3.6.13
- SylixOS 移植地址：https://github.com/acoinfo/etcd
- 依赖 bbolt 移植版：https://github.com/acoinfo/bbolt

## 改动

| 文件 | 说明 |
|---|---|
| `server/storage/backend/config_sylixos.go`（新增） | `mmapSize()` 强制返回 `0`——正常 bbolt 通过 Go 分配器模拟 mmap 分配整个 mmapSize，在 SylixOS 内存受限环境会 OOM |
| `go.mod` | 4 个 replace：bbolt → 本地移植版、`golang.org/x/sys` / `go-isatty` / `logrus` → acoinfo SylixOS 分支 |

> etcd 自身是纯 Go 应用（无需 cgo），仅依赖的 bbolt 做了 SylixOS 适配。

## 编译

需要先将 bbolt 移植版放在 `../patch_deps/bbolt`（相对于 etcd 目录）：

```
etcd-workspace/
├── etcd/                  # 本仓库
└── patch_deps/
    └── bbolt/             # git clone https://github.com/acoinfo/bbolt.git
```

```Shell
cd server
CGO_ENABLED=0 GOOS=sylixos GOARCH=arm64 go build -tags netgo -o ../bin/etcd .
```

## 部署

```Shell
[root@SylixOS /apps]# chmod +x etcd
[root@SylixOS /apps]# ./etcd --data-dir=/apps/etcd-data
```

> 纯 Go 编译产物无需 `libgolib.so`。

## 注意事项

- 编译必须加 `-tags netgo`
- 详细编译步骤见《Golang 应用移植指导手册》etcd 移植章节
