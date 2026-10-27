class_name LobbyExitResult
extends RefCounted
## Docs/02 §2.2.

enum Route { START_GAME, MATCH }
var route: Route = Route.START_GAME
## START_GAME: toast for the 게임하기 screen. "" when the player left on purpose.
var notice: String = ""
## MATCH only.
var match_setup: MatchSetup
