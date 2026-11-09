@tool
class_name ProjectileData
extends HitData
## One projectile type: its numbers here, how it moves and reacts in `behavior`.
## launch_direction follows the way the projectile is traveling, not the shooter's facing.

## VANISH disappears on the first hit; PIERCE keeps going and hits each target once.
enum AfterHit { VANISH, PIERCE }

## Names shown by the character tools (TuningForm).
const PROJECTILE_LABELS := {
	"size": ["판정 크기", "투사체 중심을 기준으로 한 폭과 높이"],
	"speed": ["속도", "발사 속도"],
	"lifetime_frames": ["수명", "사라질 때까지의 프레임. 0이면 장외 라인까지"],
	"max_active": ["동시 개수", "한 사람이 동시에 낼 수 있는 개수. 0이면 자체 제한 없음"],
	"after_hit": ["맞힌 뒤", "상대를 맞힌 뒤의 처리", ["사라짐", "관통"]],
	"hits_platforms": ["플랫폼에 막힘", "켜면 플랫폼에 닿았을 때 동작 스크립트가 처리한다 (기본은 사라짐)"],
	"behavior": ["동작", "어떻게 움직이는지. 없음은 직선 비행"],
	"@Look": "그림",
	"sprite": ["그림", "PNG. 비우면 쏜 사람의 슬롯 색 상자"],
	"sprite_height": ["그림 높이", "0이면 판정 높이에 맞춘다"],
	"rotates_with_travel": ["방향대로 회전", "켜면 날아가는 방향으로 그림을 돌린다"],
}

## Hit area in px, centered on the projectile.
@export var size: Vector2 = Vector2(24, 24)
## Launch speed in px/s.
@export_range(0.0, 1600.0, 5.0, "or_greater", "suffix:px/s") var speed: float = 400.0
## Frames until it expires (60 per second). 0 keeps it until it leaves the blast zone.
@export_range(0, 600, 1, "or_greater", "suffix:f") var lifetime_frames: int = 90
## How many of this type one fighter can have out at once. 0 sets no limit of its own.
@export_range(0, 20, 1, "or_greater", "suffix:개") var max_active: int = 0
@export var after_hit: AfterHit = AfterHit.VANISH
## Touching a platform calls the behavior's on_platform (by default it disappears).
@export var hits_platforms: bool = false
## Movement and reactions. Empty flies straight at a constant speed.
@export var behavior: ProjectileBehavior

@export_group("Look")
## PNG drawn at the hit area. Empty draws a box in the owner's slot color.
@export var sprite: Texture2D
## Drawn height in px. 0 matches the hit area.
@export_range(0.0, 400.0, 1.0, "or_greater", "suffix:px") var sprite_height: float = 0.0
## Turns the PNG toward the direction of travel instead of only flipping left and right.
@export var rotates_with_travel: bool = false
