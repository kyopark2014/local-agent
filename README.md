# Agent 애플리케이션의 구현

Mac에서 단독 실행하는 MCP/Skill 기반 로컬 에이전트입니다.

- **권장 UI:** SwiftUI 네이티브 앱 ([`MacApp/`](MacApp/))
- **백엔드:** Python FastAPI + LangGraph (포트 8501)
- **LLM:** Amazon Bedrock
- **지식:** Bedrock Knowledge Base **조회(retrieve)** + 문서 **S3 업로드 / KB sync**
- **도구:** 로컬 MCP(stdio) + 로컬 Skills
- **제외:** CloudFront 공유 URL(선택), AgentCore Gateway 웹검색, AgentCore Memory

Optional: React Web UI (`./run_local.sh`) — 개발/디버그용.

## 아키텍처

```text
Seyeon.app (SwiftUI / macOS)
    │  REST + SSE + cookie
    │  (auto-starts uvicorn)
    ▼
FastAPI (application/server.py :8501)
    │  chat.run_agent(...)
    ▼
LangGraph + local MCP + Skills + Bedrock
    └─ Knowledge Base retrieve
```

### 애플리케이션 구현

네이티브 Mac 클라이언트는 [`MacApp/`](MacApp/) 아래 **Swift / SwiftUI**로 구현되어 있으며, 제품 표시 이름은 **Seyeon**입니다. Python 백엔드와는 HTTP로만 통신하고, UI·세션·프로세스 기동은 앱이 담당합니다.

#### 사용 기술

| 영역 | 기술 |
|------|------|
| 언어·UI | Swift 5.9, SwiftUI (macOS 14+) |
| 프로젝트 생성 | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`MacApp/project.yml` → `LocalAgent.xcodeproj`) |
| 패키지 | Swift Package Manager — [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui) (GFM 마크다운 렌더) |
| 네트워킹 | `URLSession` REST + **SSE** 스트리밍, `HTTPCookieStorage`로 세션 쿠키 유지 |
| 백엔드 연동 | 로컬 FastAPI `http://127.0.0.1:8501` |
| 프로세스 | `Process`로 `scripts/run_api.sh`(uvicorn) 자동 기동 |
| 리소스 | Asset Catalog 앱 아이콘, App Sandbox **OFF** (Python·로컬 파일 접근) |

#### 구현 구조 (`MacApp/LocalAgent/`)

- **`LocalAgentApp` / `RootView`** — 윈도우·온보딩(User ID)·메인 레이아웃
- **`AppState`** — `@MainActor` ObservableObject. Task/메시지/스트리밍/설정 상태와 API·프로세스 오케스트레이션
- **`APIClient`** — `/api/session`, tasks, chat SSE, 파일 업로드, config 등
- **`PythonProcessManager`** — health 확인 후 미기동 시 백엔드 프로세스 spawn
- **`Views/`** — 사이드바(PINNED/TASKS, Skill·MCP·Model 인라인 패널), 채팅, Tool 타임라인, 설정 시트
- **`Theme/`** — Codex 스타일 다크 테마, 스크롤바 커스텀(AppKit `NSScroller`)

#### 동작 흐름

1. 앱 기동 → `/api/health` 확인 → 실패 시 `run_api.sh`로 uvicorn 기동
2. User ID로 `/api/session` 설정(쿠키) → Task 목록·config 로드
3. 채팅 전송 → SSE로 `token` / `text` / `tool` / `tool_result` / `done` 수신
4. UI는 **타임라인 순서**(AI 텍스트 → Tool → Tool result → 최종 답변)로 렌더. Tool 직전에 진행 중 텍스트를 flush해 순서가 뒤집히지 않게 함
5. 이미지 첨부는 로컬 `application/uploads/`로 업로드 후 메시지에 URL 포함

#### 백엔드(참고)

에이전트 본체는 Python **FastAPI + LangGraph**이며, Bedrock LLM·Knowledge Base retrieve·로컬 MCP/Skills를 사용합니다. Mac 앱은 이 API의 클라이언트일 뿐, 웹(React) UI와 동일한 백엔드를 공유할 수 있습니다.

## 사전 요구사항

- macOS 14+
- Python 3.11+ (`pip install -r requirements.txt`)
- AWS 자격증명 (Bedrock Runtime + Bedrock Agent Runtime retrieve)
- 기존 Knowledge Base ID
- Xcode 15+ (네이티브 앱 빌드) 또는 Swift 6 toolchain (`swift build`)

선택 (스킬별): Node 20, LibreOffice, tesseract, Chrome/Playwright

## 설정

```bash
cp application/config.json.example application/config.json
# 또는
python scripts/setup_config.py
```

`config.json`에 다음을 확인하세요.

| 키 | 설명 |
|----|------|
| `knowledge_base_id` / `knowledge_base_name` | Bedrock KB |
| `s3_bucket` | RAG 문서 업로드 버킷 (예: `storage-for-rag-project-<accountId>-<region>`) |
| `data_source_id` | 없으면 기동 시 KB의 S3 data source에서 자동 조회 |

## Build and Run

Swift를 몰라도 됩니다. **Xcode에서 ▶ 버튼만 누르면** 됩니다.

### 0) Python 백엔드 준비 (최초 1회)

```bash
cd /Users/ksdyb/Documents/src/local-agent
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp application/config.json.example application/config.json
# 또는: python scripts/setup_config.py
```

### 1) Xcode 설치 (최초 1회)

App Store에서 **Xcode**를 설치합니다. (용량이 크고 시간이 걸립니다.)

설치 후 터미널에서 한 번:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

`xcodegen`이 없으면:

```bash
brew install xcodegen
```

### 2) 프로젝트 열기

```bash
cd /Users/ksdyb/Documents/src/local-agent/MacApp
xcodegen generate
open LocalAgent.xcodeproj
```

### 3) 실행

1. 상단 타깃이 **LocalAgent**인지 확인
2. 왼쪽 위 **▶ (Run)** 또는 **⌘R**
3. 처음이면 **User ID** 입력
4. 앱이 Python 서버(`scripts/run_api.sh`)를 알아서 기동합니다
5. 채팅창에서 메시지를 보내면 됩니다

API만 따로 띄울 때:

```bash
./scripts/run_api.sh
```

Swift 소스 컴파일만 확인할 때 (Xcode GUI 없이):

```bash
cd MacApp && swift build
```

자세한 내용: [MacApp/README.md](MacApp/README.md)

### macOS 배포 패키지 (`.app` / `.dmg` / `.zip`)

```bash
chmod +x scripts/build_macos_release.sh
./scripts/build_macos_release.sh
```

결과물은 `dist/` 에 생성됩니다.

| 파일 | 설명 |
|------|------|
| `dist/Seyeon.app` | 실행 앱 |
| `dist/Seyeon-*-macos.dmg` | Applications 드래그 설치용 |
| `dist/Seyeon-*-macos.zip` | 압축 배포용 |

앱은 로컬 Python 백엔드(`local-agent` 저장소)가 필요합니다. 경로가 다르면 **Settings → Repo root**를 지정하세요.

### Web UI로 실행 (optional)

Xcode 설치 전이거나 웹으로 보고 싶을 때:

```bash
cd /Users/ksdyb/Documents/src/local-agent
source .venv/bin/activate
cd application && npm install && cd web && npm install && npm run build && cd ../..
./run_local.sh
```

브라우저: [http://localhost:8501](http://localhost:8501)

## 파일·아티팩트

- 채팅 이미지 → `application/uploads/`
- Agent 산출물 → `application/artifacts/`
- Task/메시지 → SQLite (`application/data/`)

## MCP / Skills

- **유지:** knowledge base, tavily, filesystem, korea_weather, browser-use, outlook 등
- **제외:** AgentCore Gateway `websearch`, AgentCore Memory MCP
- KB 문서: `+` → Upload to RAG (S3 `docs/` + Knowledge Base ingestion)
- 채팅 이미지 → `application/uploads/` (붙여넣기/드래그)
