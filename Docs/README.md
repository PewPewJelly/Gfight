# Docs 목록

문서를 새로 만들거나 상태가 바뀌면 이 표를 함께 고칩니다.

상태: **현행** = 지금 구현 기준 · **참고** = 일부만 유효 · **보관** = 더 이상 기준 아님(기록용)

코드 주석의 `Docs/00`, `Docs/02 §3.6` 같은 표기는 `Docs/system/00_…`, `Docs/system/02-…` 문서 번호를 뜻합니다.

## system/ 시스템 명세 (화면·구조)

| 문서 | 상태 | 내용 |
|---|---|---|
| [00_System_Context.md](system/00_System_Context.md) | 현행 | 전역 규칙: 기술 스택, 코딩 규칙, 데이터 구조, 아키텍처 |
| [01-start-game-spec.md](system/01-start-game-spec.md) | 현행 | SYS-01 게임하기 화면 |
| [02-lobby-spec.md](system/02-lobby-spec.md) | 현행 | SYS-02 대기방 |
| [03-multi_spec.md](system/03-multi_spec.md) | 현행 | 온라인 멀티플레이 구조 계획 |
| [system-review-feedback.md](system/system-review-feedback.md) | 참고 | 00~02 문서 검토 의견 (2026-10-27) |

## gdd/ 게임 규칙

| 문서 | 상태 | 내용 |
|---|---|---|
| [implementation-status.md](gdd/implementation-status.md) | 현행 | 구현 현황과 임시값. 코드와 문서가 다르면 여기를 먼저 봅니다 |
| [basicRule.md](gdd/basicRule.md) | 참고 | 기본 규칙 핸드오프 |
| [match-menu-multiplayer-handoff.md](gdd/match-menu-multiplayer-handoff.md) | 참고 | 경기 규칙·메뉴·멀티플레이 핸드오프 |
| [movement-jump-handoff.md](gdd/movement-jump-handoff.md) | 참고 | 이동·점프 핸드오프 |
| [platform-ground-collision-handoff.md](gdd/platform-ground-collision-handoff.md) | 참고 | 플랫폼·땅 판정 핸드오프 |
| [attack-handoff.md](gdd/attack-handoff.md) | 참고 | 공격 핸드오프 |
| [defeatNrule.md](gdd/defeatNrule.md) | 참고 | 장외·패배 규칙 핸드오프 |
| [defeat-implementation.md](gdd/defeat-implementation.md) | 참고 | 장외·패배 구현 기록 |
| [characters/character-template.md](gdd/characters/character-template.md) | 현행 | 캐릭터 기획서 양식 (작업실이 자동 복사) |
| [characters/kit-rules.md](gdd/characters/kit-rules.md) | 현행 | 캐릭터 고유 코드 규칙 |
| [characters/workshop-guide.md](gdd/characters/workshop-guide.md) | 현행 | 캐릭터 작업실 사용법 |
| [characters/test_fighter.md](gdd/characters/test_fighter.md) | 현행 | 테스트 파이터 기획서 |

## design/ UI·UX 디자인

| 문서 | 상태 | 내용 |
|---|---|---|
| [ui-ux-direction.md](design/ui-ux-direction.md) | 현행 | 2026-11-09 UI/UX 결정 9개와 화면별 개선 방향. 이후 UI 작업 기준 |
| [ui-ux-scenes-v2.pdf](design/ui-ux-scenes-v2.pdf) | 참고 | 경기 HUD(S3)·결과(S4)는 아직 이 문서가 기준 |
| [match-flow-scene-ux.md](design/match-flow-scene-ux.md) | 참고 | S1·S1-1은 system/01로 대체됨. S3·S4 부분만 유효 |

## archive/ 보관

| 문서 | 내용 |
|---|---|
| [01-start-game-spec-v0.3.md](archive/01-start-game-spec-v0.3.md) | system/01의 옛 버전(v0.3) |
