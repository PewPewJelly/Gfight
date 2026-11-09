# Gfight

2D 플랫폼 난투 게임입니다. 최대 4인, 3스톡, 넉백 배율 방식이며 Godot 4.7(GDScript)로 만듭니다.

## 실행

1. Godot **4.7.2** 표준판으로 `project.godot`을 엽니다.
2. F5로 실행합니다. 첫 화면은 메인 메뉴입니다.
3. 온라인·훈련장 사용법은 [`Docs/gdd/implementation-status.md`](Docs/gdd/implementation-status.md) "실행 및 참가"에 있습니다.

## 테스트

Windows PowerShell에서 실행합니다.

```powershell
tests/run_checks.ps1 -GodotPath "C:\경로\Godot_v4.7.2.exe"
```

## 폴더 지도

| 폴더 | 내용 |
|---|---|
| `Docs/` | 모든 문서. 목록은 [`Docs/README.md`](Docs/README.md) |
| `scenes/` | 화면(`ui/`)과 개발 도구(`tools/`) 씬 |
| `scripts/` | 게임 코드. `data/` 데이터 클래스, `ui/` 화면, `projectiles/` 투사체, `tools/` 개발 도구 |
| `resources/` | 조정 값(`.tres`), 캐릭터, 폰트, 셰이더 |
| `assets/` | 그림 파일(SVG 등). 설명은 [`assets/README.md`](assets/README.md) |
| `addons/` | `character_workshop`(캐릭터 작업실), `webrtc_native`(온라인 대전) |
| `tests/` | 헤드리스 테스트 |
| 루트 | `main.tscn`(시작 씬), `arena.tscn`(경기장), `project.godot` |

## 작업 규칙

- `main`에 직접 커밋하지 않습니다. 브랜치를 만들고 PR로 합칩니다.
- AI 도구로 작업할 때는 [`AI_GODOT_GUIDE.md`](AI_GODOT_GUIDE.md)를 따릅니다 (Claude Code는 `CLAUDE.md`로 자동으로 읽습니다).
