class_name MainMenuEnterData
extends RefCounted
## Entering the main menu again from another screen. null data = a plain main menu.

## Reopen the PLAY submenu (coming back from the online screen or the training lobby).
var open_play_menu: bool = false
## MainMenuScreen.PlayItem value to highlight in the submenu.
var play_item: int = 0
