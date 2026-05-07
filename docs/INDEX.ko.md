# Cotor 문서 인덱스

원문: [INDEX.md](INDEX.md)

이 문서는 **현재 제품 문서**와 **과거 기록/설계 기록**을 구분해서 찾기 위한 라우터입니다.

## 현재 제품 문서

- `README.md` / `README.ko.md`: 최상위 제품 스냅샷
- `docs/README.md` / `docs/README.ko.md`: 문서 진입 가이드
- `docs/QUICK_START.md`: 첫 설치와 첫 실행
- `docs/HOMEBREW_INSTALL.md` / `docs/HOMEBREW_INSTALL.ko.md`: packaged 설치, 첫 실행 경로, Homebrew 문제 해결
- `docs/TROUBLESHOOTING.md` / `docs/TROUBLESHOOTING.ko.md`: 데스크톱, 회사 런타임, GitHub, QA/CEO, 인터랙티브 문제 해결
- `docs/FEATURES.md` / `docs/FEATURES.ko.md`: 코드 기준 기능 목록
- `docs/CAPABILITIES.md` / `docs/CAPABILITIES.ko.md`: 에이전트 capability profile, 안전 기본값, API, CLI
- `docs/PROVIDERS.md` / `docs/PROVIDERS.ko.md`: 네트워크 없는 local provider scan 카탈로그와 명령
- `docs/DESKTOP_APP.md` / `docs/DESKTOP_APP.ko.md`: `app-server`, Company/TUI 셸, 다중 회사 UI
- `docs/TEST_PLAN.md` / `docs/TEST_PLAN.ko.md`: 자동/CLI/데스크톱/자율 회사 검증 계획
- `docs/FULL_E2E_QA_CHECKLIST.ko.md`: CLI, app-server, desktop, company runtime, GitHub, capability/security, browser/video, provider/model, evidence/graphify, web, packaging 전체 E2E 체크리스트
- `docs/FULL_E2E_QA_RESULTS.ko.md`: 최근 전체 E2E QA 결과 보고서
- `docs/USAGE_TIPS.md` / `docs/USAGE_TIPS.ko.md`: 운영 팁과 복구 습관
- `docs/WEB_EDITOR.md` / `docs/WEB_EDITOR.ko.md`: 웹 에디터 사용법
- `docs/ARCHITECTURE.md` / `docs/ARCHITECTURE.ko.md`: 공용 런타임 아키텍처
- `docs/modules.md` / `docs/modules.ko.md`: 모듈 경계 라우터
- `docs/modules/README.md` / `docs/modules/README.ko.md`: 모듈 책임, public entrypoint, 의존 방향, 테스트 위치
- `docs/CODEBASE_DEEP_DIVE.ko.md`: CLI, app-server, desktop, company runtime를 코드 기준으로 해부한 정밀 분석 문서
- `docs/CONDITION_DSL.md` / `docs/CONDITION_DSL.ko.md`: 조건 DSL 참조
- `docs/cookbook.md`: 시나리오 패턴과 예제 워크플로우
- `docs/CLAUDE_SETUP.md`: Claude 연동 설정
- `docs/OPENCODE_AGENT.md` / `docs/OPENCODE_AGENT.ko.md`: OpenCode agent 설정과 문제 해결
- `docs/team-ops/README.md` / `docs/team-ops/README.ko.md`: 온보딩과 전달 운영
- `docs/templates/temp-cotor-template.md`: 템플릿 메모
- `graphify-out/GRAPH_REPORT.md`: assistant orientation용 Graphify 구조 리포트. `graphify-out/graph.json` 전체를 prompt나 문서에 붙여 넣지 않습니다.

## 과거 기록 / 설계 문서

- `docs/reports/*`: 과거 보고서와 벤치마크 노트
- `docs/release/CHANGELOG.md`: 릴리스 이력
- `docs/release/FEATURES_v1.1.md`: 버전 시점 기능 스냅샷
- `docs/DIFFERENTIATED_PRD_ARCHITECTURE.md`: 전략/아키텍처 초안
- `docs/MULTI_WORKSPACE_REMOTE_RUNNER.md`: 러너 설계 초안
- `docs/UPGRADE_RECOMMENDATIONS.md`: 업그레이드 제안 메모
- `docs/IMPROVEMENT_ISSUES.md` / `docs/IMPROVEMENT_ISSUES.ko.md`: 과거 개선 이슈 추적
- `docs/ci-failure-analysis.md` / `docs/ci-failure-analysis.ko.md`: CI 장애 분석 메모

## 현재 진실 규칙

- 명령어 가용성은 `src/main/kotlin/com/cotor/Main.kt`와 일치해야 합니다.
- 데스크톱/회사 워크플로 동작은 `src/main/kotlin/com/cotor/app/*`, `macos/Sources/CotorDesktopApp/*`와 일치해야 합니다.
- 모듈 경계 설명은 `docs/ARCHITECTURE.md`, `docs/modules/README.md`, 현재 import graph와 일치해야 합니다.
- source 또는 docs 변경 후 `graphify update .`를 실행합니다. 큰 경계 변경 뒤에는 `graphify cluster-only .`도 실행합니다.
- “Linear 스타일 보드” 같은 표현은 Cotor 내부 UI 모양을 뜻하며, 외부 제품 실동기화를 뜻하지 않습니다.
- 과거 기록은 맥락용으로만 읽고, 현재 동작의 소스 오브 트루스로 취급하면 안 됩니다.
