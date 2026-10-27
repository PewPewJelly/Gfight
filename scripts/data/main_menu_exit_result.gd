class_name MainMenuExitResult
extends RefCounted
## Leaving the main menu (SYS-00 is not written yet: only [게임하기] leads anywhere).

enum Route { START_GAME }
var route: Route = Route.START_GAME
