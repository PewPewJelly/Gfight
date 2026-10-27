class_name MatchExitResult
extends RefCounted
## Leaving the match screen (no spec yet: keeps the existing S3/S4 flow).

enum Route { LOBBY, START_GAME }
var route: Route = Route.LOBBY
var notice: String = ""
