[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [繁體中文](README.zh-TW.md)

# Antigravity 無損多語言啟動器（繁體中文）

> **支援系統**：macOS & Windows（內建原生腳本，**無需安裝 Node.js**）  
> **中文化範圍**：主工作台、設定面板、MCP / 擴充市集、Skills & Rules、代理程式與自動化、懸浮提示 (Tooltip)、首次啟動引導頁 ＋ **AI 思考過程與回答全鏈路繁體中文化**

不解包、不改寫 `app.asar`、不破壞官方簽章。在保留原版英文 `Antigravity` 的同時，新增獨立的 **「Antigravity 繁體中文」** 雙圖示入口，官方自動更新後依然有效。

> 💡 **同作者配套工具**：如果你同時在使用 **Antigravity / Codex / Claude Code**，想在手機掃碼查看進度、批核權限或用 3D 看板統管多代理，推薦搭配開源控制台 👉 **[RemoDeck](https://github.com/guuguo/remodeck)**（[更多工具見 hub.guuguo.top](https://hub.guuguo.top)）。

![Antigravity 繁體中文 UI](docs/assets/real-ui-zh-tw.png)

## ⚡ 為什麼選擇「無損啟動器」而非傳統 `app.asar` 改包？

| 對比項目 | 傳統改包方案（解包重寫 `app.asar`） | 本專案 `antigravity-zh-launcher` |
| :--- | :--- | :--- |
| **原版安全與簽章** | 改寫官方套件，macOS 需強制重簽章，易觸發損毀攔截 | **100% 零修改原版檔案**，完整保留 Google 官方簽章 |
| **官方版本升級** | 每次更新都會覆蓋 `app.asar`，必須重新打補丁 | **更新零衝突**，外掛啟動器持續生效 |
| **對話與程式碼保護** | 全域字串替換容易把對話氣泡與程式碼內的英文誤翻 | **嚴格 DOM 邊界隔離**，絕不誤傷使用者訊息、程式碼區塊與回覆內文 |
| **AI 思考與回覆語言** | 僅翻譯介面按鈕，AI 思考與產出仍常跳回英文 | **連動語言 Prompt 外掛**，介面 + 思考鏈路 + 回覆統一使用繁體中文 |
| **雙版本並存** | 覆蓋單一安裝，想對照英文原詞需先還原 | **原版與繁中雙圖示並存**，隨時自由切換 |

## 🚀 一行指令快速安裝（繁體中文 `zh-TW`）

請先安裝官方 [Google Antigravity](https://antigravity.google)（執行時無需 Node.js）。

**macOS：**
```bash
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.sh | bash -s -- --lang zh-TW
```

**Windows PowerShell：**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.ps1))) --lang zh-TW
```

## 🛠️ 日常使用與無痕解除安裝

- **啟動**：直接點擊應用程式或桌面上的 **`Antigravity 繁體中文`** 圖示，或執行 `agy-zh-tw start`。
- **切回原版英文**：關閉視窗後點擊原本的 **`Antigravity`** 圖示即可，繁中語言規則外掛會自動關閉。

```bash
# 解除安裝（macOS）
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.sh | bash -s -- --lang zh-TW --purge
```
```powershell
# 解除安裝（Windows PowerShell）
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.ps1))) --lang zh-TW --purge
```

## 🔗 同系列配套開源工具

- **[RemoDeck](https://github.com/guuguo/remodeck)** — 電腦與手機統一遠端控制 **Antigravity / Codex / Claude Code / Grok** 的自託管控制台，支援 5 秒掃碼核准權限、多帳號額度分離與 3D 夢工廠即時看板。
- **[guuguo 工具主頁](https://hub.guuguo.top)** — 查看更多開源桌面工具與 AI 工作流專案。

---

[官方介紹頁](https://hub.guuguo.top/antigravity-zh) · [MIT License](LICENSE) · [CLI 詳細說明](docs/usage.en.md)
