class_name LobbyExitResult
extends RefCounted
## Docs/02 §2.2.

enum Route { MENU, MATCH }
var route: Route = Route.MENU
## MENU: toast for the screen the player returns to. "" when the player left on purpose.
var notice: String = ""
## MATCH only.
var match_setup: MatchSetup
