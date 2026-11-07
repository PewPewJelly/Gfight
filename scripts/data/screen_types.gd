class_name ScreenTypes
extends RefCounted
## Shared screen enums (Docs/00 §3.1). ONLINE is the temporary online screen that replaced
## 게임하기 (START_GAME) when the PLAY submenu moved into the main menu.

enum ScreenId { MAIN_MENU, ONLINE, LOBBY, MATCH, RESULT, GUIDEBOOK, SETTINGS }
enum RoomMode { NONE, ONLINE, TRAINING }
enum Role { NONE, HOST, CLIENT }
