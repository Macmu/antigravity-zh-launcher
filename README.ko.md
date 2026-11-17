[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [繁體中文](README.zh-TW.md)

# Antigravity 무손실 다국어 런처 (한국어 지원)

> **지원 OS**: macOS & Windows (시스템 기본 스크립트 사용, **Node.js 설치 불필요**)  
> **현지화 범위**: 메인 워크벤치, 설정 패널, MCP / 플러그인 마켓플레이스, Skills & Rules, 자동화, 툴팁, 초기 안내 모달 + **AI 사고 과정(Thinking) 및 답변 한국어화**

`app.asar` 언패킹이나 바이너리 패치 없이 원본 영문 `Antigravity`를 그대로 유지하면서 독립된 **`Antigravity 한국어`** 실행 아이콘을 생성합니다. macOS 코드 서명이 깨지지 않으며 공식 업데이트 후에도 풀리지 않습니다.

![Antigravity 한국어 UI](docs/assets/real-ui-ko.png)

## ⚡ 기존 `app.asar` 패치 방식과의 차이점

| 비교 항목 | 기존 `app.asar` 직접 수정 방식 | 본 프로젝트 (`antigravity-zh-launcher`) |
| :--- | :--- | :--- |
| **코드 서명 및 안전성** | 원본 앱 수정으로 macOS Gatekeeper 경고 발생 가능 | **원본 앱 100% 무수정**, 공식 코드 서명 완벽 유지 |
| **업데이트 호환성** | 공식 업데이트 때마다 초기화되어 재설치 필요 | **업데이트 충돌 없음**, 외부 런처로 그대로 유지 |
| **채팅 및 코드 보호** | 채팅 메시지나 코드 속 영단어까지 오번역되는 문제 발생 | **엄격한 DOM 경계 분리**로 사용자 메시지·코드 블록·에디터 보존 |
| **AI 사고 과정 및 답변** | UI 메뉴만 번역되어 AI 응답은 영어로 돌아가는 경우 많음 | **언어 규칙 플러그인 연동**으로 사고 과정·도구 요약·답변까지 한국어 유도 |
| **원본 영문판 병행 사용** | 덮어쓰기 방식이라 영문 확인 시 제거 필요 | **듀얼 아이콘 공존**으로 영문판과 한국어판 자유롭게 선택 실행 |

## 🚀 한 줄 설치 (한국어 `ko`)

먼저 공식 [Google Antigravity](https://antigravity.google)를 설치해 주세요 (Node.js 불필요).

**macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.sh | bash -s -- --lang ko
```

**Windows PowerShell:**
```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/install.ps1))) --lang ko
```

## 🛠️ 사용 및 깔끔한 제거

- **실행**: 응용 프로그램 / 바탕화면의 **`Antigravity 한국어`** 아이콘 클릭 또는 `agy-ko start` 실행.
- **순정 영문판 전환**: 종료 후 기존 **`Antigravity`** 아이콘으로 실행하면 한국어 프롬프트 규칙도 자동으로 꺼집니다.
- **9개 언어 지원**: `zh-CN`, `zh-TW`, `ja`, `ko`, `es`, `fr`, `de`, `ru`, `pt-BR`.

```bash
# 제거 (macOS)
curl -fsSL https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.sh | bash -s -- --lang ko --purge
```
```powershell
# 제거 (Windows PowerShell)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/guuguo/antigravity-zh-launcher/main/uninstall.ps1))) --lang ko --purge
```

[공식 소개 페이지](https://hub.guuguo.top/antigravity-zh) · [MIT License](LICENSE) · [CLI 상세 문서](docs/usage.en.md)
