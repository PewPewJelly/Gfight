class_name MainMenuExitResult
extends RefCounted
## Leaving the main menu from the PLAY submenu (SYS-00 is not written yet: only PLAY leads
## anywhere). TRAINING has already opened the training room through Session.start_training().

enum Route { ONLINE, TRAINING }
var route: Route = Route.ONLINE
