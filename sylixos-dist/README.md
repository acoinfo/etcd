# etcd for SylixOS (RK3568) — 修复版预编译包

**这个包解决什么问题**：SylixOS 上跑 etcd 内存持续增长（Linux 同集群约 400MB，SylixOS 能到 5G 以上且从不回落）。
根因有两层，**都已经修好了**：

| 层 | 问题 | 修复位置 |
|---|---|---|
| Go runtime | `sysUnusedOS` 是空实现 —— 它是 scavenger 归还物理页的**唯一出口**，空了就导致 Go 堆内存只进不出 | Go 源码 `acoinfo/go:sylixos-patch_on_go1.25`（含 `sysUnusedOS`/`sysUsedOS` 实现） |
| bbolt 移植 | 扩容时缓存旧 buffer + 1.5× 预留 → 新旧两份同时在场 | `acoinfo/bbolt` main（`8895ecc`，早前已修） |
| **etcd 启动配置** | **`auto-compaction` 默认关闭** → DB 无界增长 → 内存无上界 | **本包的 `etcd.conf.yml`** |

> **第三项不是可选的。** 只修 runtime/bbolt、不加配置，DB 仍会无界增长，
> 内存照样涨（实测：DB 566MB → 进程占用 1602MB 且仍在波动）。
> 加上配置后：DB 被限在 255.9MB，进程内存 1032MB 且**到达稳态后完全静止**。

---

## 快速开始

```
1) 上传到板子（FTP，被动模式）：
     etcd          ->  /apps/etcd
     etcd.conf.yml ->  /apps/etcd.conf.yml

2) 改配置里的 IP：把 etcd.conf.yml 中所有 <BOARD_IP>
   替换成板子的实际 IP（etcd 要 advertise 一个可达地址，不能留 localhost）

3) 启动：
     cd /apps
     ./etcd --config-file=etcd.conf.yml
```

**注意**：SylixOS 的 shell **不支持 `>` 重定向**，所以不要用 `./etcd ... > log`，
要么不要重定向，要么用 `--log-outputs` 之类的 etcd 自己的参数。

---

## 验证它确实生效了

**① 先确认二进制是修复版**（最关键的一行）：

```
./etcd --version
```

输出**不应该**包含 `ExpandSizeStep=`。
- 出现 `ExpandSizeStep=134217728` → **是旧的、没修的版本**
- 没有这一行 → 修复版 ✓

（那行 printf 只存在于修复前的 bbolt 移植代码里，是最省事的判别标志。）

**② 看进程内存口径**：

```
ps            # 看 etcd 那行的 MEMORY 列（这是 VMM 口径，即监控面板看到的数字）
free          # 看 VMM-Physical memory free，这是物理真相
```

**③ 压一阵写入后停止写入、观察 60 秒**：修复版的特征是内存**能回落**
（`free` 的 VMM free 回升），旧版是**只降不升**。

---

## 已知限制（诚实说明，不是遗漏）

1. **地址空间碎片化** —— `mmap(MAP_FIXED)` 是 VMA 级操作，每次回收会切分映射。
   实测 region 数 54→97（未修）变成 2718→6282（已修），**83 倍**，线性增长无收敛。
   etcd 在 6282 个 region 时仍正常工作、写入速率未退化，但**上限未知**。
   这是刻意接受的取舍：所有替代方案（`mprotect(PROT_NONE)`、`posix_madvise`、
   `mmap RW`）都在板上量过，**全部不释放物理页**，只有 `PROT_NONE + MAP_FIXED` 能用。

2. **归还速率约 1MB/s**（Go scavenger 的渐进策略，非缺陷）。

3. **活跃 buffer（约 1.1×DB）不可回收** —— 是活对象。所以**配额是让内存有上界的唯一手段**。

4. **配额耗尽后** etcd 会进入拒写状态并报 `NOSPACE` 告警；compaction 释放空间后需要
   `etcdctl alarm disarm` 才恢复写入 —— **这是预期行为，不是故障**。

---

## 想自己编？不用重建工具链

如果你要用修的 Go 源码自己编译：

```
1) 取 Go 源码（含 sysUnusedOS 修复）：
     git clone https://github.com/acoinfo/go.git  -b sylixos-patch_on_go1.25

2) 直接用它的 GOROOT 编，**关键是加 -a**：
     export GOROOT=<go源码目录>
     export GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=sylixos GOARCH=arm64
     cd etcd/server && go build -a -tags netgo -o ../bin/etcd .

3) etcd 的 go.mod 需要指向 bbolt 移植版：
     replace go.etcd.io/bbolt => <路径>/bbolt      # 公司 bbolt main 已是修复版
```

> **`-a` 是关键**：改动只在 `src/runtime/` 下，`-a` 会强制从源码重编 runtime，
> **不需要跑 `make.bat` 重建工具链**。
> （只有改 `src/cmd/link/*` 链接器才需要 `make.bat`。）

---

## 本包的来源

- 二进制：用 `acoinfo/go` 的 `sylixos-patch_on_go1.25` 分支编译，
  `go build -a -tags netgo`，`etcd v3.6.13` / `go1.25.0` / `sylixos/arm64`
- 已验证：最小程序分配 384MB → 回收 384MB（99.5%）；etcd 完整写入压测
  （DB 553MB 时 `heap_sys` 2375MB / 板子 VMM 空闲 1456MB，观察期各指标完全静止）；
  真实 KV 模式复测（8KB 小 value + 30% 读）行为一致
