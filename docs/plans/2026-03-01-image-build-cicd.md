# Image Build CI/CD Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** `main` ブランチ更新時に GHCR へコンテナイメージを自動で build/push できる状態を作る。

**Architecture:** Zola サイトを Docker マルチステージで生成し、最終ステージを Nginx で配信する。GitHub Actions で checkout（submodule 含む）→ metadata 生成→ GHCR ログイン→ build/push を実行する。

**Tech Stack:** Docker, GitHub Actions, GHCR, Zola, Node.js

---

### Task 1: 実装計画と進行管理ファイル作成

**Files:**
- Create: `docs/plans/2026-03-01-image-build-cicd.md`
- Create: `tasks/todo.md`

**Step 1: 計画書を作成する**

`docs/plans/2026-03-01-image-build-cicd.md` を作成し、目的・制約・実装手順・検証手順を明記する。

**Step 2: 実施タスクをチェックリスト化する**

`tasks/todo.md` にチェック可能な項目を作成し、進捗更新ルールを定義する。

**Step 3: ファイルの存在を確認する**

Run: `ls docs/plans tasks`
Expected: `docs/plans` と `tasks` が存在する。

### Task 2: Dockerfile 実装

**Files:**
- Create: `Dockerfile`

**Step 1: ビルドステージを作成する**

Node.js ベースイメージで `npm install` と `npm run abridge` を実行し、`public/` を生成する。

**Step 2: ランタイムステージを作成する**

Nginx ベースイメージへ `public/` を配置し、80 番ポートで配信できるようにする。

**Step 3: ローカルビルドを実行する**

Run: `docker build -t cabalascan:test .`
Expected: build が成功し、`public/` がランタイムにコピーされる。

### Task 3: GitHub Actions ワークフロー実装

**Files:**
- Create: `.github/workflows/build-image.yml`

**Step 1: トリガーと権限を定義する**

`main` への push と `workflow_dispatch` をトリガーにし、`packages: write` を設定する。

**Step 2: GHCR push 手順を定義する**

`docker/login-action` と `docker/build-push-action` で `ghcr.io/${{ github.repository }}` に push する。

**Step 3: タグ戦略を定義する**

`latest` と `sha-<short>` 相当タグを生成する。

**Step 4: workflow 構文検証を実行する**

Run: `actionlint`
Expected: エラー 0 件。

### Task 4: 検証と記録

**Files:**
- Modify: `tasks/todo.md`

**Step 1: 静的検証結果を記録する**

`actionlint` 結果を `tasks/todo.md` に反映する。

**Step 2: 動的検証結果を記録する**

`docker build` 実行結果を `tasks/todo.md` に反映する。

**Step 3: レビューセクションを追加する**

実装要約・検証結果・残リスクを `tasks/todo.md` 末尾に追記する。
