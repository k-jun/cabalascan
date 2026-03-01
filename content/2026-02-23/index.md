+++
date = "2026-02-23"
title = "ch-vmm: KubeVirt に代わる軽量 VM Manager を試す"

[taxonomies]
tags = ["Kubernetes", "Virtualization", "ch-vmm", "Cloud Hypervisor", "Homelab"]
[extra]
toc = true

+++

こんにちは、k-jun です。今回は Kubernetes 上で軽量に VM を動かせる [ch-vmm](https://github.com/nalajala4naresh/ch-vmm) を、実際に Homelab で検証した結果を紹介します。

<!-- more -->

## ch-vmm とは

ch-vmm は、Kubernetes 上で [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor) の VM を動かすための add-on です。KubeVirt と同じ領域のツールですが、architecture が大きく異なります。

## なぜ KubeVirt ではなく ch-vmm なのか

KubeVirt は Kubernetes 上の VM 管理として最も major な選択肢ですが、いくつかの課題があります。

- **QEMU + libvirt に依存**: attack surface が広く、memory 消費も大きい
- **Pod あたりの常駐 process**: launcher process が VM ごとに ≈80MB 消費する
- **heavyweight な構成**: libvirt daemon を挟むため、構成が複雑

ch-vmm はこれらを以下のように解決します。

| | KubeVirt | ch-vmm |
|---|---|---|
| Hypervisor | QEMU + libvirt | Cloud Hypervisor |
| VM あたりの memory overhead | ≈110MB+ | ≈30MB |
| 常駐 launcher process | あり (≈80MB) | なし |
| Snapshot / Restore | あり (重い) | あり (軽量) |
| VMPool / VMSet | なし | あり |
| Cloud Hypervisor version | - | v50.0 対応 |

## Architecture

ch-vmm は 3 つの component で構成されます。

1. **ch-vmm-controller**: cluster 全体の controller。Cloud Hypervisor VM を動かす Pod を作成する
2. **ch-daemon**: node ごとの daemon。各 node 上の VM を制御する
3. **virt-prerunner**: Pod ごとの pre-runner。VM の network 準備と Cloud Hypervisor の設定ファイル生成を担当する

KubeVirt のように libvirt daemon を挟まないため、構成が simple です。

## 前提条件

- Kubernetes v1.35+（v1.2.0 以降。In-place vertical scaling 対応）
  - v1.35 未満の場合は v1.1.0 を使用
- `/dev/kvm` が各 node に存在すること（hardware virtualization support）
- [cert-manager](https://cert-manager.io/) v1.16+
- Container runtime: Docker または containerd

## Install

```bash
# cert-manager の install
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml

# ch-vmm の deploy
kubectl apply -f https://github.com/nalajala4naresh/ch-vmm/releases/latest/download/ch-vmm.yaml

# CDI operator（DataVolume で disk 管理するため）
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```

## VM を作成してみる

以下の manifest で Ubuntu の VM を作成できます。

```yaml
apiVersion: cloudhypervisor.quill.today/v1beta1
kind: VirtualMachine
metadata:
  name: ubuntu-container-rootfs
spec:
  runPolicy: Once
  instance:
    cpu:
      sockets: 1
      coresPerSocket: 1
      threadsPerCore: 1
    memory:
      size: 512Mi
    kernel:
      image: quay.io/ch-vmm/kernel:6.12.1
    rootDisk:
      image: quay.io/ch-vmm/ubuntu-container-rootfs:22.04
      size: 10Gi
```

```bash
kubectl apply -f vm.yaml
kubectl get vm
```

たったこれだけで Kubernetes 上に VM が立ち上がります。

## VMPool で複数 VM を管理する

ch-vmm 独自の機能として VMPool があります。教育 platform のように複数 user に VM を払い出す use case で便利です。

```yaml
apiVersion: cloudhypervisor.quill.today/v1beta1
kind: VMPool
metadata:
  name: training-pool
spec:
  replicas: 5
  template:
    spec:
      runPolicy: Once
      instance:
        cpu:
          sockets: 1
          coresPerSocket: 1
          threadsPerCore: 1
        memory:
          size: 512Mi
        kernel:
          image: quay.io/ch-vmm/kernel:6.12.1
        rootDisk:
          image: quay.io/ch-vmm/ubuntu-container-rootfs:22.04
          size: 10Gi
```

これで同一 spec の VM を 5 台まとめて作成できます。

## 起動速度: KubeVirt vs ch-vmm

実際に Homelab (N100 node) で計測した結果です。

### 計測条件

- Guest: Ubuntu Jammy cloud image
- Resource: 1 vCPU / 1Gi
- Storage: `local-path`（同一 StorageClass）
- 計測回数: 各 5 回

### Status 到達時間（API level で Running になるまで）

| Engine | min | p50 | max | avg |
|---|---|---|---|---|
| **ch-vmm** | 26s | 28s | 29s | **27.6s** |
| **KubeVirt** | 5s | 6s | 6s | **5.8s** |

API level では KubeVirt が約 4.8 倍速い。

### SSH 到達時間（実際に VM を使えるまで）

| Engine | min | p50 | max | avg |
|---|---|---|---|---|
| **ch-vmm** | 24s | 26s | 27s | **25.8s** |
| **KubeVirt** | 42s | 44s | 45s | **44.0s** |

**実用的な「VM が使える」までの速度では ch-vmm が 1.7 倍速い。**

### なぜ逆転するのか

KubeVirt の Status=Running は「QEMU process が起動した」時点であり、guest OS の boot 完了ではありません。一方 ch-vmm は Cloud Hypervisor 自体の起動が **≈60ms** と極めて高速で、guest OS の boot が先に終わります。

ch-vmm の E2E 28s の内訳:

| Phase | 所要時間 | 内容 |
|---|---|---|
| Pod 作成 → Pod Ready | ~5s | K8s scheduling |
| vm-manager → vm.sock 出現 | ~5s | prerunner が CH の設定を生成 |
| vm.sock → VM Boot | **~60ms** | **Cloud Hypervisor 本体の起動** |
| VMBooted → VM Ready=True | ~15s | daemon の status polling 間隔 |

Cloud Hypervisor の起動は 60ms。bottleneck は control plane の実装にあります。

## Guest OS 最適化

SSH 到達時間をさらに短縮するため、guest OS 内の不要 service を削減しました。

### 施策

1. **snapd 完全除去**: `snapd.service` (2.2s) + `snapd.seeded.service` (2.7s) を排除
2. **不要 systemd unit を mask**: `lvm2-monitor`, `multipathd`, `plymouth-*` 等
3. **cloud-init module を最小化**: `set-passwords` + `ssh` のみ

### 結果

| 指標 | 最適化前 | 最適化後 | 差分 |
|---|---|---|---|
| kernel | 1.8s | 1.7s | -0.1s |
| userspace | 14.1s | 9.5s | **-4.6s** |
| **合計** | **15.9s** | **11.2s** | **-4.7s (30% 改善)** |

ただし **E2E SSH 到達時間はほぼ変わりませんでした**。Guest OS は control plane の overhead (~10s) の裏側で並行起動しており、guest 起動がこれ以上速くなっても control plane が律速になるためです。

## Fork による control plane 高速化

Guest OS 最適化の限界が判明したため、ch-vmm 本体を fork して daemon の status polling 間隔を 15s → 1s に変更しました。

### 結果

**Status 到達時間:**

| | 元 (15s polling) | Fork 後 (1s polling) |
|---|---|---|
| avg | 27.6s | **17.0s** |

**38% 改善。最速 12s。**

### 総合比較

| 指標 | ch-vmm (元) | ch-vmm (fork) | KubeVirt | 勝者 |
|---|---|---|---|---|
| Status 到達 | 27.6s | 17.0s | 5.8s | KubeVirt |
| SSH 到達 | 25.8s | 24.8s | 44.0s | **ch-vmm** |

実用的な SSH 到達時間では、ch-vmm が KubeVirt の約 1.8 倍速いという結果になりました。

## Snapshot / Restore

ch-vmm は VM の snapshot と restore を support しています。

### Snapshot

GCS bucket への snapshot は成功しました。Memory snapshot (zstd 圧縮) が 49 MiB で upload されます。

```yaml
apiVersion: cloudhypervisor.quill.today/v1beta1
kind: VMSnapShot
metadata:
  name: gcs-snapshot-test
spec:
  vm: ubuntu-container-rootfs
  bucket: gcs://k-jun-ch-vmm-snapshots-gcs
```

### Restore の課題

Restore は現状いくつかの問題があります。

1. **Cloud 認証の問題**: controller が prerunner Pod を生成する際に GCS/S3 の認証情報を渡さない。Kyverno の Mutating Webhook で注入することで回避可能
2. **Network の不整合**: memory snapshot から復元された VM は snapshot 時点の NIC/IP 設定を保持しているため、新しい Pod の network に追従できない
3. **v1.1.0 の既知 bug**: rollback controller の値渡し問題、`skipMemorySnapshot: true` でも memory volume が追加される等

現時点では snapshot は検証用途に限定し、restore は upstream の修正を待つか fork で対応する必要があります。

## 注意点

ch-vmm はまだ WIP (Work In Progress) の project です。

- API が予告なく変更される可能性がある
- 本番環境での利用実績はまだ少ない
- K8s v1.35+ が必要なため、現時点では対応 cluster が限られる
- Snapshot/Restore は部分的にしか動作しない

## まとめ

| 項目 | 結論 |
|---|---|
| VM 起動 (SSH 到達) | ch-vmm が KubeVirt の **1.8 倍速い** |
| Memory overhead | ch-vmm が **≈80MB 少ない** |
| Cloud Hypervisor 起動 | **≈60ms**（VMM 単体は圧倒的） |
| Snapshot | GCS/S3 に対応、動作する |
| Restore | 現状 bug あり、実用は要 fork |
| Control plane | polling 間隔が bottleneck。fork で改善可能 |

Resource が限られた Homelab 環境（N100 / 8-16GB RAM）では KubeVirt より ch-vmm のほうが適していると感じています。特に教育 platform のように多数の軽量 VM を払い出す use case では、memory overhead の差が効いてきます。

ch-vmm はまだ荒削りですが、Cloud Hypervisor の性能を Kubernetes から引き出せる点で大きな可能性を感じています。今後も動向を追いかけていきます。それでは！
