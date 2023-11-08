extends HBoxContainer

signal join_pressed(lobby_name : String, has_password : bool)

var has_password : bool

func set_lobby_data(data : Dictionary):
	name = data["Name"]
	has_password = data["HasPassword"]
	%LobbyName.text = name
	%PlayerCount.text = str(data["PlayerCount"])+"/"+str(data["PlayerLimit"])
	%PasswordProtected.text = str(has_password).capitalize()
	%Open.text = str(data["Open"]).capitalize()
	
	%JoinButton.disabled = !data["Open"]
	
	var tags : Dictionary = data["Tags"]
	if tags.has("Gamemode"): %Gamemode.text = tags["Gamemode"]


func _on_join_button_pressed():
	join_pressed.emit(name, has_password)
