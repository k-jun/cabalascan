# TODO

- [x] 計画書を `docs/plans/2026-03-01-image-build-cicd.md` に作成する
- [x] `Dockerfile` を追加して Zola ビルド済み成果物を配信可能にする
- [x] `.github/workflows/build-image.yml` を追加して GHCR push CI/CD を作る
- [x] `actionlint` で workflow の静的検証を実行する
- [x] `docker build` でイメージ build の動的検証を実行する
- [x] 実行ログと判定結果を記録してレビューセクションを追加する

## 進捗メモ

- Dockerfile は `npm run abridge` を実行して `public/` を生成し、Nginx へ配置するマルチステージ構成にした。
- Docker build で `themes` が build context に含まれないケースに備えて、`themes/abridge` が無い場合のみ GitHub から clone するフォールバックを追加した。
- Zola 0.20 系は `generate_feed` 非互換のため、サイト設定に合わせて Zola 0.17.2 を採用した。

## 検証ログ

### 静的検証

```sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest
```

- 判定: 成功（出力なし / エラー 0 件）

### 動的検証

```sh
docker build --platform linux/amd64 -t cabalascan:test .
```

- 主要出力: `RUN npm run abridge` が成功し、最終的に `naming to docker.io/library/cabalascan:test done`
- 判定: 成功

```sh
docker run --rm -d --name cabalascan-test -p 18080:80 cabalascan:test && sleep 2 && curl -I http://127.0.0.1:18080 && docker stop cabalascan-test
```

- 主要出力: `HTTP/1.1 200 OK`
- 判定: 成功

## レビュー

- Why: 既存 GHCR イメージ更新を手動から自動化し、`main` 更新時に確実に最新イメージを配布するため。
- What: `Dockerfile`、`.dockerignore`、`.github/workflows/build-image.yml` を追加し、GHCR push の CI/CD を構築した。
- How: `actionlint` と `docker build/run` による静的・動的検証を実行し、成功を確認した。
