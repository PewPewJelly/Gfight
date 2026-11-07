class_name OnlineExitResult
extends RefCounted
## Leaving the temporary online screen (fields from Docs/01 §2.2).

enum Route { MAIN_MENU, LOBBY }
var route: Route = Route.MAIN_MENU
var room_mode: ScreenTypes.RoomMode = ScreenTypes.RoomMode.NONE
var role: ScreenTypes.Role = ScreenTypes.Role.NONE
## Online lobby: Session.room.address ("IP:port"); otherwise "".
var room_address: String = ""
