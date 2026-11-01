# assets

Docs/00·01·02 명세에 나오는 아이콘과 그림을 SVG로 옮긴 것. 단색 아이콘은 흰색으로 그렸으므로 Godot에서 `modulate`/`self_modulate`로 색을 입힌다.

| 파일 | 크기(viewBox) | 출처 | 쓰는 곳 |
|---|---|---|---|
| start_game/sword.svg | 240×240 | 01 §3.2 `sword_icon.gd` 수치 그대로 | 게임하기 화면 실전 아이콘 |
| start_game/target.svg | 240×240 | 01 §3.2 `target_icon.gd` (중심점 #ff5a5a) | 게임하기 화면 훈련장 아이콘 |
| icons/x, o, v, star, back, info, dots, mute, play, lock, copy | 64×64 | 02 §3.3 `LobbyIcons.Kind` 11종 | 대기방 준비 버튼, 카드, 메뉴, 팝오버 |
| characters/test_fighter.svg | 256×256 | `scripts/fighter.gd` 모양(36×52 상자 + 방향선) 3배 | 대기방 `CharacterArt` |
| characters/random.svg | 256×256 | 02 §3.3 `random` = `?` | 캐릭터 랜덤 칸(2종 이상일 때) |
| maps/test_map.svg | 640×360 | `scripts/arena.gd` 발판 배치 50% 축소 | 대기방 `MapArt` |
| maps/random.svg | 640×360 | 02 §3.3 `random` = 큰 `?` | 맵 랜덤 칸(2종 이상일 때) |

preview.png는 전체 미리보기.

쓰는 규칙은 Docs/00 §1 UI 원칙, 01 §3.2, 02 §3.3 (2026-10-27 SVG 전환). 캐릭터·맵 파일 이름은 카탈로그 id와 같아야 한다.
