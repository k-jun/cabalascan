+++
date = "2026-02-23"
title = "ch-vmm: KubeVirt に代わる軽量 VM マネージャーを試す"

[taxonomies]
tags = ["Kubernetes", "Virtualization", "ch-vmm", "Cloud Hypervisor", "Homelab"]
[extra]
toc = true

+++

こんにちは、k-jun です。今回は Kubernetes 上で軽量に仮想マシンを動かせる [ch-vmm](https://github.com/nalajala4naresh/ch-vmm) を紹介します。

<!-- more -->

## ch-vmm とは

ch-vmm は、Kubernetes 上で [Cloud Hypervisor](https://github.com/cloud-hypervisor/cloud-hypervisor) の仮想マシンを動かすためのアドオンです。KubeVirt と同じ領域のツールですが、アーキテクチャが大きく異なります。

## なぜ KubeVirt ではなく ch-vmm なのか

KubeVirt は Kubernetes 上の VM 管理として最もメジャーな選択肢ですが、いくつかの課題があります。

- **QEMU + libvirt に依存**: アタックサーフェスが広く、メモリ消費も大きい
- **Pod あたりの常駐プロセス**: launcher プロセスが VM ごとに≈80MB 消費する
- **スナップショット/リストア**: 機能としてはあるが、仕組みが重い

ch-vmm はこれらを以下のように解決します。

| | KubeVirt | ch-vmm |
|---|---|---|
| ハイパーバイザー | QEMU + libvirt | Cloud Hypervisor |
| VM あたりのメモリオーバーヘッド | ≈110MB+ | ≈30MB |
| 常駐ランチャープロセス | あり (≈80MB) | なし |
| スナップショット/リストア | あり (重い) | あり (軽量) |
| VMPool / VMSet | なし | あり |
| Cloud Hypervisor バージョン | - | v50.0 対応 |

## アーキテクチャ

ch-vmm は3つのコンポーネントで構成されます。

1. **ch-vmm-controller**: クラスタ全体のコントローラー。Cloud Hypervisor VM を動かす Pod を作成する
2. **ch-daemon**: ノードごとのデーモン。各ノード上の VM を制御する
3. **virt-prerunner**: Pod ごとのプレランナー。VM のネットワーク準備と設定ファイルの生成を担当する

KubeVirt のように libvirt デーモンを挟まないため、構成がシンプルです。

## 前提条件

- Kubernetes v1.35+（v1.2.0 以降。In-place vertical scaling 対応）
  - v1.35 未満の場合は v1.1.0 を使用
- `/dev/kvm` が各ノードに存在すること（ハードウェア仮想化サポート）
- [cert-manager](https://cert-manager.io/) v1.16+
- コンテナランタイム: Docker または containerd

## インストール

```bash
# cert-manager のインストール
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.1/cert-manager.yaml

# ch-vmm のデプロイ
kubectl apply -f https://github.com/nalajala4naresh/ch-vmm/releases/latest/download/ch-vmm.yaml

# CDI operator（DataVolume でディスク管理するため）
export VERSION=$(curl -s https://api.github.com/repos/kubevirt/containerized-data-importer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-operator.yaml
kubectl create -f https://github.com/kubevirt/containerized-data-importer/releases/download/$VERSION/cdi-cr.yaml
```

## VM を作成してみる

以下のマニフェストで Ubuntu の VM を作成できます。

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

たったこれだけで Kubernetes 上に VM が立ち上がります。KubeVirt と比べてマニフェストもシンプルです。

## VMPool で複数 VM を管理する

ch-vmm 独自の機能として、VMPool があります。教育プラットフォームのように複数ユーザーに VM を払い出すケースで便利です。

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

これで同一スペックの VM を5台まとめて作成できます。

## スナップショット/リストア

ch-vmm は VM のスナップショットとリストアをサポートしています。これは VirtInk にはない機能で、ch-vmm を選ぶ大きな理由のひとつです。

ユーザーが環境を壊してしまった場合に、スナップショットから即座に復元できるのは教育用途において非常に重要です。

## 注意点

ch-vmm はまだ WIP（Work In Progress）のプロジェクトです。

- API が予告なく変更される可能性がある
- 本番環境での利用実績はまだ少ない
- K8s v1.35+ が必要なため、現時点では対応クラスタが限られる

とはいえ、Cloud Hypervisor ベースの軽量さとスナップショット機能は魅力的です。KubeVirt が重すぎると感じている方や、教育・トレーニング用途で VM を大量に払い出したい方には、検討する価値があると思います。

## まとめ

- ch-vmm は Cloud Hypervisor を使った軽量な K8s VM マネージャー
- KubeVirt と比べてメモリオーバーヘッドが大幅に少ない
- VMPool / スナップショット / リストアが標準で使える
- まだ WIP だが、軽量 VM が必要なユースケースでは有力な選択肢

個人的には、Homelab の N100 マシン（メモリ 8〜16GB）のようなリソースが限られた環境では、KubeVirt より ch-vmm のほうが適していると感じています。

今後も ch-vmm の動向を追いかけていきます。それでは！
