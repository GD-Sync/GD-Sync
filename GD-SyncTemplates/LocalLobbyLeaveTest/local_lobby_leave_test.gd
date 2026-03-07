extends Control
## Minimal scene to replicate GD-Sync issue #109:
## GDSync.lobby_leave() throws when using Local Multiplayer (start_local_multiplayer).
## Steps: Start local -> Create or join lobby -> Leave lobby.

@onready var status_label: Label = %StatusLabel
@onready var btn_start_local: Button = %BtnStartLocal
@onready var btn_create_lobby: Button = %BtnCreateLobby
@onready var btn_join_lobby: Button = %BtnJoinLobby
@onready var btn_leave_lobby: Button = %BtnLeaveLobby

const TEST_LOBBY_NAME := "Issue109TestLobby"

func _ready() -> void:
	btn_start_local.pressed.connect(_on_start_local_pressed)
	btn_create_lobby.pressed.connect(_on_create_lobby_pressed)
	btn_join_lobby.pressed.connect(_on_join_lobby_pressed)
	btn_leave_lobby.pressed.connect(_on_leave_lobby_pressed)
	GDSync.connected.connect(_on_connected)
	GDSync.lobby_created.connect(_on_lobby_created)
	GDSync.lobby_joined.connect(_on_lobby_joined)
	GDSync.connection_failed.connect(_on_connection_failed)
	GDSync.lobby_join_failed.connect(_on_lobby_join_failed)
	_update_buttons()
	_set_status("Ready. Click Start local multiplayer.")

func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text

func _update_buttons() -> void:
	var connected: bool = GDSync.get_client_id() >= 0
	if btn_start_local:
		btn_start_local.disabled = connected
	if btn_create_lobby:
		btn_create_lobby.disabled = !connected
	if btn_join_lobby:
		btn_join_lobby.disabled = !connected
	if btn_leave_lobby:
		btn_leave_lobby.disabled = !connected

func _on_start_local_pressed() -> void:
	_set_status("Starting local multiplayer...")
	GDSync.start_local_multiplayer()

func _on_connected() -> void:
	_set_status("Connected (local). Create or join a lobby, then Leave lobby to test #109.")
	_update_buttons()

func _on_connection_failed(_reason: int) -> void:
	_set_status("Connection failed. See output.")
	_update_buttons()

func _on_create_lobby_pressed() -> void:
	_set_status("Creating lobby '%s'..." % TEST_LOBBY_NAME)
	GDSync.lobby_create(TEST_LOBBY_NAME, "", true, 0, {}, {})

func _on_lobby_created(_name: String) -> void:
	_set_status("Lobby created. Click Leave lobby to test issue #109.")
	_update_buttons()

func _on_join_lobby_pressed() -> void:
	_set_status("Joining lobby '%s'..." % TEST_LOBBY_NAME)
	GDSync.lobby_join(TEST_LOBBY_NAME, "")

func _on_lobby_joined(_name: String) -> void:
	_set_status("Joined lobby. Click Leave lobby to test issue #109.")
	_update_buttons()

func _on_lobby_join_failed(_name: String, _err: int) -> void:
	_set_status("Join failed (create lobby on first instance first).")
	_update_buttons()

func _on_leave_lobby_pressed() -> void:
	_set_status("Leaving lobby (this used to throw in LocalServer.gd:451)...")
	GDSync.lobby_leave()
	_set_status("Left lobby. If no error in console, issue #109 is fixed.")
	_update_buttons()
