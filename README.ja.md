[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [繁體中文](README.zh-TW.md)

# Antigravity 非破壊・多言語ランチャー（日本語対応）

> **対応 OS**：macOS / Windows（標準スクリプトのみ・**Node.js 不要**）  
> **日本語化範囲**：メイン画面、設定パネル、MCP / プラグインマーケット、Skills & Rules、オートメーション、ツールチップ、初回案内ダイアログ ＋ **AI の思考プロセス・回答の日本語化**

`app.asar` の書き換えや再署名を一切行わず、元の英語版 `Antigravity` を無傷のまま残して **「Antigravity 日本語」** アイコンを追加します。macOS のコード署名を壊さず、本体の自動アップデートでも上書きされません。

![Antigravity 日本語 UI](docs/assets/real-ui-ja.png)

## ⚡ 従来の `app.asar` パッチ方式との違い

| 比較項目 | 従来の `app.asar` 書き換え型 | 本プロジェクト (`antigravity-zh-launcher`) |
| :--- | :--- | :--- |
| **コード署名と安全性** | アプリ本体を改変するため macOS で署名エラーのリスクあり | **本体ファイル無改変**・Google 公式のコード署名を完全維持 |
| **本体アップデート耐性** | アップデートのたびに上書きされ再パッチが必要 | **アップデート競合なし**・そのまま継続利用可能 |
| **チャット・コード保護** | チャット内やコード中の英単語まで誤翻訳されることがある | **DOM 境界を厳密に分離**（ユーザー発言・コード・エディタは翻訳しない） |
| **AI の思考・返答言語** | UI のみ翻訳（AI の思考やプランが英語に戻りがち） | **専用プロンプトルール連動**で思考ログ・要約・回答まで日本語に統一 |
| **英語版との併用** | 上書き型のため切り替えにアンインストールが必要 | **デュアルアイコン並存**（元の英語版と日本語版をいつでも使い分け） |

## 🚀 ワンライナー導入（日本語 `ja`）

先に公式の [Google Antigravity](https://antigravity.google) をインストールしてください（Node.js は不要です）。

**macOS：**
```bash
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.sh | bash -s -- --lang ja
```

**Windows PowerShell：**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.ps1))) --lang ja
```

ローカルクローンから導入する場合：`bash install.sh --lang ja` / `powershell -ExecutionPolicy Bypass -File .\install.ps1 --lang ja`

## 🛠️ 使い方・アンインストール

- **起動**：アプリケーションフォルダ / デスクトップの **`Antigravity 日本語`** アイコン、または `agy-ja start` で起動します。
- **元の英語版に戻す**：セッション終了後に元の **`Antigravity`** アイコンから起動すると、日本語プロンプト設定も自動でオフになります。
- **他言語の追加**：`zh-CN` / `zh-TW` / `ja` / `ko` / `es` / `fr` / `de` / `ru` / `pt-BR` の 9 言語に対応。

```bash
# アンインストール（macOS）
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.sh | bash -s -- --lang ja --purge
```
```powershell
# アンインストール（Windows PowerShell）
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.ps1))) --lang ja --purge
```

[公式サイト](https://hub.guuguo.top/antigravity-zh) · [MIT License](LICENSE) · [CLI 詳細](docs/usage.en.md)
