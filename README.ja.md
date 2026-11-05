<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail" width="880"></p>

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · **日本語** · [한국어](README.ko.md) · [简体中文](README.zh-Hans.md)

# Monkeytail

**iPhone、iPad、Mac、Apple Vision Pro 向けのネイティブ API クライアント。Postman や Insomnia のコレクションをそのまま持ち込み、スクリプトも使い続けられます。サインインは不要です。**

Monkeytail は手持ちのコレクションを開き、同じように実行します。Monkeytail のアカウントも、ログイン画面も、クラウドのワークスペースも、テレメトリもありません。リクエストはサーバに直接送られ、データはデバイスか自分の iCloud Drive に保存されます。

<p><img src="docs/screenshots/iphone-request.png" alt="iPhone のリクエストエディタ" width="285"> <img src="docs/screenshots/iphone-response.png" alt="iPhone の JSON レスポンス" width="285"></p>

## Postman や Insomnia からの乗り換え

- **すべて読み込めます。** Postman のコレクション（v1、v2、v2.1）、環境、グローバル変数、データの一括エクスポート、Insomnia v4・v5 のエクスポートに加え、Bruno、Hoppscotch、Thunder Client、HAR、`.http` ファイル、OpenAPI/Swagger、cURL に対応。複数のファイルやフォルダをまとめて選べます。
- **クラウドから直接取り込むこともできます。** Postman、Insomnia、Hoppscotch に一度サインインして同期済みのワークスペースを取り込むか、GitHub リポジトリを指定します。セッションはその読み込みにだけ使われ、保存されません。
- **スクリプトはそのまま動きます。** リクエスト前スクリプトとテストスクリプトは、`pm.test`、`pm.expect`、`pm.sendRequest`、CryptoJS、lodash、moment を含む Postman 互換の `pm` API で実行されます。Insomnia、Bruno などのスクリプトも互換オブジェクトを通じて動作します。
- **使い方も同じです。** 認証、ヘッダ、変数、スクリプトを継承するワークスペース、コレクション、入れ子のフォルダ。環境、グローバル変数、`{{$guid}}` のような動的変数を含む `{{変数}}` も使えます。
- **いつでも書き出せます。** Postman v2.1、Insomnia v4、または情報を失わない Monkeytail の JSON ファイル。

## そのほかの機能

- HTTP、イントロスペクション対応の GraphQL、WebSocket、Server-Sent Events
- OAuth 2.0（PKCE）、OAuth 1.0、JWT、AWS Signature V4、Digest、API キー、Basic、Bearer
- 反復と CSV/JSON データファイルに対応したコレクションランナー。JSON または JUnit のレポートを書き出し
- ビジュアルなアサーション、保存した例、オフラインのモック、ローカルのモックサーバ
- 整形した JSON、ツリー、検索、比較、画像、オーディオ、ビデオ、16 進数を表示するレスポンスビューア
- 13 の言語でのコード生成と、cURL の読み込み・書き出し
- 所要時間の内訳、TLS の詳細、HTTP/HTTPS/SOCKS5 プロキシ、クライアント証明書、任意のブラウザ TLS プロファイル
- テーマ、独自の色とフォント。英語、スペイン語、フランス語、日本語、韓国語、簡体字中国語に対応
- 自分の iCloud Drive での同期と、お気に入りのリクエストを送れる Apple Watch 用コンパニオン

詳細：[API ツール](docs/APITools.md) · [スクリプト](docs/Scripting.md) · [ブラウザプロファイル](docs/BrowserProfiles.md) · [サンプルワークスペース](docs/examples)

## ビルド

Xcode で `Monkeytail.xcodeproj` を開き、**Monkeytail**（iPhone と iPad）、**MonkeytailMac**、**MonkeytailVision** のいずれかのスキームを実行します。iOS 17、macOS 14、visionOS 1 以降が必要です。`project.yml` を編集したら `xcodegen generate` を実行してください。

## テスト

```sh
swift test
```

## ライセンス

[BSD 3-Clause](LICENSE)
