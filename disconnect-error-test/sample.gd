extends Control
## Issue #109 test: GDSync.lobby_leave() with Local Multiplayer.
## Run 2 instances: Instance 1 = Start local → Create lobby. Instance 2 = Start local → Join lobby → Leave lobby.

@onready var status_label: Label = %StatusLabel
@onready var btn_start_local: Button = %BtnStartLocal
@onready var btn_create_lobby: Button = %BtnCreateLobby
@onready var btn_join_lobby: Button = %BtnJoinLobby
@onready var btn_leave_lobby: Button = %BtnLeaveLobby

const TEST_LOBBY_NAME := "Issue109TestLobby"

func _ready() -> void:
	print("[Issue109] Sample ready. GDSync autoload present: ", GDSync != null)
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
	_set_status("Ready. Click Start local (run 2 instances to test host+client).")

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
	print("[Issue109] Start local pressed -> calling GDSync.start_local_multiplayer()")
	_set_status("Starting local multiplayer...")
	GDSync.start_local_multiplayer()

func _on_connected() -> void:
	print("[Issue109] Connected. client_id=", GDSync.get_client_id())
	_set_status("Connected (local). Create lobby (instance 1) or Join then Leave (instance 2).")
	_update_buttons()

func _on_connection_failed(_reason: int) -> void:
	print("[Issue109] Connection failed. reason=", _reason)
	_set_status("Connection failed. See output.")
	_update_buttons()

func _on_create_lobby_pressed() -> void:
	print("[Issue109] Create lobby pressed -> GDSync.lobby_create('%s')" % TEST_LOBBY_NAME)
	_set_status("Creating lobby '%s'..." % TEST_LOBBY_NAME)
	GDSync.lobby_create(TEST_LOBBY_NAME, "", true, 0, {}, {})

func _on_lobby_created(_name: String) -> void:
	print("[Issue109] Lobby created: '%s' (host ready for peers)" % _name)
	_set_status("Lobby created. On 2nd instance: Join then Leave lobby.")
	_update_buttons()

func _on_join_lobby_pressed() -> void:
	print("[Issue109] Join lobby pressed -> GDSync.lobby_join('%s')" % TEST_LOBBY_NAME)
	_set_status("Joining lobby '%s'..." % TEST_LOBBY_NAME)
	GDSync.lobby_join(TEST_LOBBY_NAME, "")

func _on_lobby_joined(_name: String) -> void:
	print("[Issue109] Lobby joined: '%s' client_id=" % _name, GDSync.get_client_id())
	_set_status("Joined. Click Leave lobby to test issue #109.")
	_update_buttons()

func _on_lobby_join_failed(_name: String, _err: int) -> void:
	print("[Issue109] Lobby join failed: name='", _name, "' error=", _err)
	_set_status("Join failed (create lobby on first instance first).")
	_update_buttons()

func _on_leave_lobby_pressed() -> void:
	print("[Issue109] Leave lobby pressed -> calling GDSync.lobby_leave()")
	_set_status("Leaving lobby...")
	GDSync.lobby_leave()
	print("[Issue109] lobby_leave() returned. (No console error = #109 fixed.)")
	_set_status("Left lobby. No console error = #109 fixed.")
	_update_buttons()
