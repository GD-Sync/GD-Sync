extends Control

signal join_pressed(lobby_name : String, has_password : bool)

var LABEL_SCENE : PackedScene = preload("res://GD-SyncTemplates/LobbyBrowser/lobby_label.tscn")

func _ready():
#	Connect signal related to retrieving lobbies
	GDSync.lobbies_received.connect(lobbies_received)

var last_refresh : float = 0
func _process(delta):
#	Refresh the lobby list every 5 seconds
	var current_time : float = Time.get_unix_time_from_system()
	if current_time - last_refresh >= 5:
		last_refresh = current_time
		
#		Request all publicly visible lobbies and wait for the signal to fire
		GDSync.get_public_lobbies()

func lobbies_received(lobbies : Array):
#	Display all lobbies using UI elements
	var lobby_labels : Array = %LobbyList.get_children()
	
#	Mark all currently displayed lobbies for deletion
	for label in lobby_labels: label.set_meta("delete", true)
	
	for lobby_data in lobbies:
		var name : String = lobby_data["Name"]
		var lobby_label : Node = %LobbyList.get_node_or_null(name)
		
		if lobby_label == null:
			lobby_label = LABEL_SCENE.instantiate()
			lobby_label.join_pressed.connect(lobby_join_pressed)
			%LobbyList.add_child(lobby_label)
		
#		Cancel deletion if the lobby still exists
		lobby_label.set_meta("delete", false)
		lobby_label.set_lobby_data(lobby_data)
	
#	Delete all old displayed lobbies
	for label in lobby_labels:
		if label.get_meta("delete"): label.queue_free()

func lobby_join_pressed(lobby_name : String, has_password : bool):
	join_pressed.emit(lobby_name, has_password)
