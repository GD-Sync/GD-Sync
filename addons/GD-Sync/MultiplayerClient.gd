extends Node
class_name MultiplayerClient

#Copyright (c) 2024 GD-Sync.
#All rights reserved.
#
#Redistribution and use in source form, with or without modification,
#are permitted provided that the following conditions are met:
#
#1. Redistributions of source code must retain the above copyright notice,
#   this list of conditions and the following disclaimer.
#
#2. Neither the name of GD-Sync nor the names of its contributors may be used
#   to endorse or promote products derived from this software without specific
#   prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
#EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
#OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
#SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
#TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
#BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
#ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
#SUCH DAMAGE.










# Signals ---------------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Emitted when the plugin successfully completes the connection and encryption handshake. 
##This signal is emitted after using [method start_multiplayer].
##If this is emitted it means you can use all other multiplayer functions.
signal connected()

##Emitted if the connection handshake failes. This signal is emitted after using [method start_multiplayer].
##[br]
##[br][b]error -[/b] The reason behind the failed connection attempt. See [constant ENUMS.CONNECTION_ERROR] for possible errors.
signal connection_failed(error : int)

##Emitted when the client disconnects. Might be due to connectivity issues or when the server goes down.
##[br]
##[br][b]IMPORTANT: The plugin does not automatically try to reconnect when a disconnect occurs.[/b]
signal disconnected()

##Emitted when the Client ID changes. This happens when using [method start_mutliplayer] and might happen 
##when using [method join_lobby]. This will NEVER happen while inside a lobby, so don't worry when 
##using methods such as [method set_gdsync_owner], [method call_func_on], etc.
signal client_id_changed(own_id : int)

##Emitted if [method create_lobby] was succesful.
##[br]
##[br][b]lobby_name -[/b] The name of the lobby that was created.
signal lobby_created(lobby_name : String)

##Emitted if [method create_lobby] failes.
##[br]
##[br][b]lobby_name -[/b] The name of the lobby that failed to create.
##[br][b]error -[/b] The reason why the creation failed. 
##Check [constant ENUMS.LOBBY_CREATION_ERROR] for possible errors.
signal lobby_creation_failed(lobby_name : String, error : int)

##Emitted when [method join_lobby] was succesful.
##[br]
##[br][b]lobby_name -[/b] The name of the lobby that the player joined.
signal lobby_joined(lobby_name : String)

##Emitted when [method join_lobby] failed.
##[br]
##[br][b]lobby_name -[/b] The name of the lobby that the player was unable to join.
##[br][b]error -[/b] The reason why the joining failed. 
##Check [constant ENUMS.LOBBY_JOIN_ERROR] for possible errors.
signal lobby_join_failed(lobby_name : String, error : int)

##Emitted when any lobby data value is changed. Emitted after [method set_lobby_data] and [method erase_lobby_data].
##[br]
##[br][b]key -[/b] The key of the data that changed.
##[br][b]value -[/b] The new value. This will be null is the data was erased.
signal lobby_data_changed(key : String, value)

##Emitted when any lobby tags value is changed. Emitted after [method set_lobby_tags] and [method erase_lobby_tags].
##[br]
##[br][b]key -[/b] The key of the tag that changed.
##[br][b]value -[/b] The new value. This will be null is the tag was erased.
signal lobby_tag_changed(key : String, value)

##Emitted when a client joins the current lobby.
##[br][b]IMPORTANT: This is emitted for all clients, [color=light_green]INCLUDING[/color] yourself when joining a lobby.[/b]
##[br]
##[br][b]client_id -[/b] The id of the client that joined.
signal client_joined(client_id : int)

##Emitted when a client leaves the current lobby.
##[br][b]IMPORTANT: This is emitted for ALL clients, [color=crimson]EXCLUDING[/color] yourself when leaving a lobby.[/b]
##[br]
##[br][b]client_id -[/b] is the id of the client that left.
signal client_left(client_id : int)

##Emitted when a player uses [method set_player_data], [method erase_player_data] or [method set_player_username]. 
##Player data is synchronized every second if it is altered.
##[br]
##[br][b]client_id -[/b] is the id of the client that left.
signal player_data_changed(client_id : int, key : String, value)

##Emitted as a result of [method get_public_lobbies].
##[br]
##[br][b]lobbies -[/b] An array of all public lobbies and their publicly available data.
signal lobbies_received(lobbies : Array)

##Emitted when the host of the current lobby changes. This might happen if the current host leaves or disconnects.
##The server automatically decides which player is the host.
##[br]
##[br]Being the host does not do anything by itself, but is something that can help you when developing authorative code.
##[br]The [PropertySynchronizer] class will also make use of this if told to do so in the inspector.
##[br]
##[br][b]is_host -[/b] A boolean that indicates if you are the new host or not.
##[br][b]new_host_id -[/b] The Client ID of the new host.
signal host_changed(is_host : bool, new_host_id : int)

##Emitted when a time synchronized event is triggered. See [method create_synced_event] for more information.
##[br]
##[br][b]event_name -[/b] The name of the event that has been triggered.
##[br][b]parameters -[/b] Any parameters binded to the event.
signal synced_event_triggered(event_name : String, parameters : Array)







# Initialization --------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

var _request_processor
var _connection_controller
var _session_controller
var _https_controller
var _data_controller
var _node_tracker

func _init():
	_request_processor = preload("res://addons/GD-Sync/Scripts/RequestProcessor.gd").new()
	_connection_controller = preload("res://addons/GD-Sync/Scripts/ConnectionController.gd").new()
	_session_controller = preload("res://addons/GD-Sync/Scripts/SessionController.gd").new()
	_https_controller = preload("res://addons/GD-Sync/Scripts/HTTPSController.gd").new()
	_data_controller = preload("res://addons/GD-Sync/Scripts/DataController.gd").new()
	_node_tracker = preload("res://addons/GD-Sync/Scripts/NodeTracker.gd").new()

func _ready():
	add_child(_request_processor)
	add_child(_connection_controller)
	add_child(_session_controller)
	add_child(_https_controller)
	add_child(_data_controller)
	add_child(_node_tracker)










# General functions -----------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Starts the GD-Sync plugin by connecting to a server. If succesful, [signal connected] will be emitted. 
##If not, [signal connection_failed] will be emitted.
func start_multiplayer() -> void:
	_connection_controller.start_multiplayer()

func stop_multiplayer() -> void:
	_connection_controller.stop_multiplayer()

##Returns true if the plugin is connected to a server. Returns false if there is no active connection.
func is_active() -> bool:
	return _connection_controller.is_active()

func _manual_connect(address : String) -> void:
	_connection_controller.connect_to_server(address)

##Returns your own Client ID. Returns -1 if you are not connected to a server.
func get_client_id() -> int:
	return _connection_controller.client_id

##Returns the Client ID of the last client to perform a remote function call on this client. 
##Useful for knowing where a remote function call came from. 
##Returns -1 if nobody performed a remote function call yet.
##[br]
##[br][b]IMPORTANT:[/b] For this function to work, make sure to enable it in the GD-Sync configuration menu.
func get_sender_id() -> int:
	return _session_controller.get_sender_id()

##Returns the client IDs of all clients in the current lobby.
func get_all_clients() -> Array:
	return _session_controller.get_all_clients()

##Returns whether you are the host of the lobby you are in.
func is_host() -> bool:
	return _connection_controller.host == get_client_id()

##Returns the Client ID of the host of the current lobby you are in. Returns -1 if you are not in a lobby.
func get_host() -> int:
	return _connection_controller.host

##Synchronizes a variable on a Node across all other clients in the current lobby.
##Make sure the NodePath on all clients matches up and that the variable is exposed using [method expose_var] or [method expose_node].
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node you want to synchronize a variable on.
##[br][b]variable_name -[/b] The name of the variable you want to synchronize.
##[br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until succesful. 
##This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.
func sync_var(node : Node, variable_name : String, reliable : bool = true) -> void:
	_request_processor.create_set_var_request(node, variable_name, -1, reliable)

##Synchronizes a variable on a Node to a specific client in the current lobby.
##Make sure the NodePath on all clients matches up and that the variable is exposed using [method expose_var] or [method expose_node].
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]client_id -[/b] The Client ID of the client you want to synchronize to.
##[br][b]node -[/b] The Node you want to synchronize a variable on.
##[br][b]variable_name -[/b] The name of the variable you want to synchronize.
##[br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until succesful. 
##This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.
func sync_var_on(client_id : int, node : Node, variable_name : String, reliable : bool = true) -> void:
	_request_processor.create_set_var_request(node, variable_name, client_id, reliable)

##Calls a function on a Node on all other clients in the current lobby.
##Make sure the NodePath on all clients matches up and that the function is exposed using [method expose_func] or [method expose_node].
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]callable -[/b] The function that you want to call.
##[br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
##[br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until succesful. 
##This may introduce more latency. Use unreliable if the function call is non-essential.
func call_func(callable : Callable, parameters = null, reliable = true) -> void:
	_request_processor.create_function_call_request(callable, parameters, -1, reliable)

##Calls a function on a Node on a specific client in the current lobby.
##Make sure the NodePath on all clients matches up and that the function is exposed using [method expose_func] or [method expose_node].
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]client_id -[/b] The Client ID of the client you want to call the function on.
##[br][b]callable -[/b] The function that you want to call.
##[br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
##[br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until succesful. 
##This may introduce more latency. Use unreliable if the function call is non-essential.
func call_func_on(client_id : int, callable : Callable, parameters = null, reliable = true) -> void:
	_request_processor.create_function_call_request(callable, parameters, client_id, reliable)

##Instantiates a Node on all clients in the current lobby.
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the parent matches up on all clients. 
##[br]
##[br][b]scene -[/b] The [PackedScene] you want to instantiate.
##[br][b]parent -[/b] The parent/location of where you want to instantiate the Node.
##[br][b]sync_starting_changes -[/b] If enabled, any changes made to the root Node of the instantiated scene 
##within the same frame will automatically be synchronized.
##[br][b]excluded_properties -[/b] Names of properties you want to exclude from sync_starting_changes. 
##[br][b]replicate_on_join -[/b] If enabled, the instantiated Node will be replicated on clients that 
##join the lobby later on.
func multiplayer_instantiate(
		scene : PackedScene,
		parent : Node,
		sync_starting_changes : bool = true,
		excluded_properties : PackedStringArray = [],
		replicate_on_join : bool = true) -> Node:
	return _node_tracker.multiplayer_instantiate(scene, parent, sync_starting_changes, excluded_properties, replicate_on_join)

##Returns a float which contains the current multiplayer time. This time is synchronized across clients in 
##the same lobby. Can be used for time-based events. See [method create_synced_event] for creating 
##time-based triggers.
##[br]
##[br][b]IMPORTANT:[/b] It may take up to a second for the time to synchronize after just joining a lobby.
func get_multiplayer_time() -> float:
	return _session_controller.synced_time

##Create a time-based event that triggers after a delay. GD-Sync will attempt to trigger this event 
##on all clients at the same time, regardless of the latency between clients. Useful for creating 
##time-critical events or mechanics. After the delay, [signal synced_event_triggered] is emitted. 
##[br]
##[br][b]IMPORTANT:[/b] If the given delay is shorter than the latency between two clients, the 
##event trigger might be delayed. It is recommended to always use a delay >= 1 second.
##[br]
##[br][b]event_name -[/b] The name of the event. Queued events can share the same name.
##[br][b]delay -[/b] The delay in seconds after which the event should be triggered.
##[br][b]parameters -[/b] Any parameters which should be binded to the event.
func create_synced_event(event_name : String, delay : float = 1.0, parameters : Array = []) -> void:
	_session_controller.register_event(event_name, get_multiplayer_time()+delay, parameters, true)










# Security & safety functions -------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##If set to true, all remote function calls and variable synchronization requests will be blocked by default. 
##Only functions, variables and Nodes that are exposed using [method expose_func], [method expose_var] and [expose_node] 
##may be accessed remotely. This setting can also be found in the configuration menu.
##[br]
##[br]
##We STRONGLY recommendd keeping this enabled at all times. Disabling it may introduce security risks.
##[br]
##[br][b]protected -[/b] If protected mode should be enabled or disabled.
func set_protection_mode(protected : bool) -> void:
	_request_processor.set_protection_mode(protected)

##Exposes a Node so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will succeed. 
##Only use if the Node and its script contain non-destructive functions. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node you want to expose.
func expose_node(node : Node) -> void:
	_session_controller.expose_node(node)

##Hides a Node so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will fail. 
##This will not revert [method expose_func] and [method expose_var]. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node you want to hide.
func hide_node(node : Node) -> void:
	_session_controller.expose_node(node)

##Exposes a function so that [method call_func] and [method call_func_on] will succeed. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]callable -[/b] The function you want to expose.
func expose_func(callable : Callable) -> void:
	_session_controller.expose_func(callable)

##Hides a function so that [method call_func] and [method call_func_on] will fail. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]callable -[/b] The function you want to hide.
func hide_function(callable : Callable) -> void:
	_session_controller.hide_function(callable)

##Exposes a variable so that [method sync_var] and [method sync_var_on] will succeed. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node on which you want to expose the variable.
##[br][b]variable_name -[/b] The name of the variable you want to expose.
func expose_var(node : Node, variable_name : String) -> void:
	_session_controller.expose_property(node, variable_name)

##Hides a variable so that [method sync_var] and [method sync_var_on] will fail. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node on which you want to hide the variable.
##[br][b]variable_name -[/b] The name of the variable you want to hide.
func hide_var(node : Node, variable_name : String) -> void:
	_session_controller.hide_property(node, variable_name)










# Node ownership --------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Sets the owner of a Node. Node ownership is recursive and will apply to all children. 
##Being the owner of a Node does not do anything by itself, but is useful when writing certain scripts. 
##For example, when you are re-using your player scene for all players, you can only execute the keyboard inputs on 
##the player of which you are the owner. 
##[br]The [PropertySynchronizer] class will also make use of this if told to do so in the inspector.
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node on which you want to assign ownership to.
##[br][b]owner -[/b] The client ID of the new owner.
func set_gdsync_owner(node : Node, owner : int) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_gdsync_owner(node, owner)

##Clears the owner of a Node. Node ownership is recursive and will be removed on all children. 
##[br]
##[br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients. 
##[br]
##[br][b]node -[/b] The Node on which you want to clear ownership.
func clear_gdsync_owner(node : Node) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_gdsync_owner(node, -1)

##Returns the Client ID of the client that has ownership of the Node. Returns -1 if there is no owner.
##[br]
##[br][b]node -[/b] The Node from which you want to retrieve the owner.
func get_gdsync_owner(node : Node) -> int:
	return _session_controller.get_gdsync_owner(node)

##Returns true if you are the owner of the Node in question. Returns false if you are not the owner or when there is not owner.
##[br]
##[br][b]node -[/b] The Node on which you want to perform the ownership check.
func is_gdsync_owner(node : Node) -> bool:
	return _session_controller.is_gdsync_owner(node)

##Connects up a signal so that a specific function gets called if the owner of the Node changes. 
##The function must have one parameter which is the Client ID of the new owner. 
##The Client ID will be -1 if the doesn't have an owner anymore
##[br]
##[br][b]node -[/b] The Node of which you want to monitor ownership.
##[br][b]callable -[/b] The function that should get called if the owner changes.
func connect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	_session_controller.connect_gdsync_owner_changed(node, callable)


##Disconnects a function from the ownership signal created in [method connect_gdsync_owner_changed].
##[br]
##[br][b]node -[/b] The Node of which you want to disconnect ownership monitoring.
##[br][b]callable -[/b] The function that should get disconnected.
func disconnect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	_session_controller.disconnect_gdsync_owner_changed(node, callable)










# Lobby functions -------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Attempts to retrieve all publicly visible lobbies from the server. 
##Will emit the signal [signal lobbies_received] once the server has collected all lobbies
func get_public_lobbies() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.get_public_lobbies()

##Attempts to create a lobby on the server. If succesful [signal lobby_created] is emitted.
##If it fails [signal lobby_creation_failed] is emitted. Creating a lobby has a cooldown of 3 seconds.
##[br]
##[br][b]name -[/b] The name of the lobby you want to create. Has a maximum of 32 characters.
##[br][b]password -[/b] The password of the lobby. Leave empty if you want everyone to be able to join without a password. 
##Has a maximum of 16 characters.
##[br][b]public -[/b] If true, the lobby will be visible when using [method get_public_lobbies]
##[br][b]player_limit -[/b] The player limit of the lobby. If 0 it will automatically be set to the maximum your plan allows. 
##This is also the case if the limit entered exceeds your plan limit.
##[br][b]tags -[/b] Any starting tags you would like to add to the lobby.
##[br][b]data -[/b] Any starting data you would like to add to the lobby.
func create_lobby(name : String, password : String = "", public : bool = true, player_limit : int = 0, tags : Dictionary = {}, data : Dictionary = {}) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_new_lobby_request(name, password, public, player_limit, tags, data)

##Attempts to join an existing lobby. If succesful [signal lobby_joined] is emitted. 
##If it fails [signal lobby_join_failed] is emitted. 
##Using this function might cause your Client ID to change when joining a lobby that is not on your current server.
##[br]
##[br][b]name -[/b] The name of the lobby you are trying to join.
##[br][b]password -[/b] The password of the lobby you are trying to join.
##If the lobby has no password this can have any value.
func join_lobby(name : String, password : String = "") -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_lobby_data(name, password)
	_request_processor.create_join_lobby_request(name, password)

##Closes the lobby you are currently in, blocking any new players from joining. The lobby will still be visible when using [method get_public_lobbies].
func close_lobby() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_close_lobby_request()

##Opens the lobby you are currently in, allowing new players to join.
func open_lobby() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_open_lobby_request()

##Sets the visibility of the lobby you are currently in. Decides whether the lobby shows up when using [method get_public_lobbies]
##[br]
##[br][b]public -[/b] If the lobby should be visible or not.
func set_lobby_visibility(public : bool) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_lobby_visiblity_request(public)

##Leaves the lobby you are currently in. This does not emit any signals.
func leave_lobby() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_leave_lobby_request()
	_session_controller.lobby_left()
	_node_tracker.lobby_left()

##Returns the amount of players in the current lobby.
func get_lobby_player_count() -> int:
	return _session_controller.get_all_clients().size()

##Get the current lobby name
func get_lobby_name() -> String:
	return GDSync._session_controller.lobby_name

##Returns the player limit of the current lobby.
func get_lobby_player_limit() -> int:
	return _session_controller.get_player_limit()

##Adds a new or updates the value of a tag. Tags are publicly visible data that is returned with [method get_public_lobbies]. 
##Especially useful when display information like the gamemode or map.
##[br]
##[br]
##This does not instantly update, so it won't have an affect on [method has_lobby_tag] and [method get_lobby_tag] until 
##a response from the server is returned. If the operation was succesful [signal lobby_tag_changed] is emitted.
##[br]
##[br][b]key -[/b] The key of the tag.
##[br][b]value -[/b] The value of the tag that should be stored.
func set_lobby_tag(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_set_lobby_tag_request(key, value)

##Deletes an existing tag.
##[br]
##[br]
##This does not instantly update, so it won't have an affect on [method has_lobby_tag] and [method get_lobby_tag] until 
##a response from the server is returned. If the operation was succesful [signal lobby_tag_changed] is emitted.
##[br]
##[br][b]key -[/b] The key of the tag.
func erase_lobby_tag(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_erase_lobby_tag_request(key)

##Returns true if a tag with the given key exists.
##[br]
##[br][b]key -[/b] The key of the tag.
func has_lobby_tag(key : String) -> bool:
	return _session_controller.has_lobby_tag(key)

##Gets the value of a lobby tag.
##[br]
##[br][b]key -[/b] The key of the tag.
##[br][b]default -[/b] The default value that is returned if the given key does not exist.
func get_lobby_tag(key : String, default = null):
	return _session_controller.get_lobby_tag(key, default)

##Returns a dictionary with all lobby tags and their values.
func get_all_lobby_tags() -> Dictionary:
	return _session_controller.get_all_lobby_tags()

##Adds new or updates existing lobby data. Data is private data that can only be viewed from inside the lobby. 
##[br]
##[br]
##This does not instantly update, so it won't have an affect on [method has_lobby_data] and [method get_lobby_data] until 
##a response from the server is returned. If operation was succesful [signal lobby_data_changed] is emitted.
##[br]
##[br][b]key -[/b] The key of the data.
##[br][b]value -[/b] The value of the data that should be stored.
func set_lobby_data(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_set_lobby_data_request(key, value)

##Deletes existing data.
##[br]
##[br]
##This does not instantly update, so it won't have an affect on [method has_lobby_data] and [method get_lobby_data] until 
##a response from the server is returned. If operation was succesful [signal lobby_data_changed] is emitted.
##[br]
##[br][b]key -[/b] The key of the tag.
func erase_lobby_data(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_erase_lobby_data_request(key)

##Returns true if data with the given key exists.
##[br]
##[br][b]key -[/b] The key of the data.
func has_lobby_data(key : String) -> bool:
	return _session_controller.has_lobby_data(key)

##Gets the value of lobby data.
##[br]
##[br][b]key -[/b] The key of the data.
##[br][b]default -[/b] The default value that is returned if the given key does not exist.
func get_lobby_data(key : String, default = null):
	return _session_controller.get_lobby_data(key, default)

##Returns a dictionary with all lobby data and their values.
func get_all_lobby_data() -> Dictionary:
	return _session_controller.get_all_lobby_data()










# Player functions ------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Sets data for your client. Player data has a maximum size of 2048 bytes, if this limit is exceeded 
##a critical error is printed. 
##Emits [signal player_data_changed]. It may take up to 1 second for this signal to be emitted, as player 
##data is synchronized every second if altered.
##[br]
##[br][b]key -[/b] The key of the player data.
##[br][b]value -[/b] The value of the player data.
func set_player_data(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_player_data(key, value)
	_request_processor.create_set_player_data_request(key, value)

##Erases data for your client. 
##Emits [signal player_data_changed] with null as the value.
##[br]
##[br][b]key -[/b] The key of the player data.
func erase_player_data(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.erase_player_data(key)
	_request_processor.create_erase_player_data_request(key)

##Gets data from a specific client. If you want to retreive your own data you can input your own id. 
##You can get your own id using [method get_client_id].
##[br]
##[br][b]client_id -[/b] The Client ID of which client you would like to get the data from.
##[br][b]key -[/b] The key of the player data.
##[br][b]default -[/b] The default value that is returned if the given key does not exist.
func get_player_data(client_id : int, key : String, default = null):
	if !_connection_controller.valid_connection(): return default
	return _session_controller.get_player_data(client_id, key, default)

##Gets all data from a specific client. If you want to retreive your own data you can input your own id. 
##You can get your own id using [method get_client_id].
##[br]
##[br][b]client_id -[/b] The Client ID of which client you would like to get the data from.
func get_all_player_data(client_id : int) -> Dictionary:
	if !_connection_controller.valid_connection(): return {}
	return _session_controller.get_all_player_data(client_id)

##Sets the username of the player. If enabled in the configuration menu, usernames can be set to unique. 
##When this setting is enabled there can be no duplicate usernames inside a lobby. 
##Emits [signal player_data_changed] with the key "Username".
##[br]
##[br][b]name -[/b] The username of this client.
func set_player_username(name : String) -> void:
	_request_processor.create_set_username_request(name)
	_session_controller.set_player_data("Username", name)










# Accounts & Persistent Data Storage ------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------

##Creates an account in the database linked to the API key. 
##[br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_CREATION_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account. The email has to be unique.
##[br][b]username -[/b] The username of the account. The username has to be unique. 
##The username has to be between 3 and 20 characters long.
##[br][b]password -[/b] The password of the account. 
##The password has to be between 3 and 20 characters long.
func create_account(email : String, username : String, password : String) -> int:
	return await _data_controller.create_account(email, username, password)

##Deletes an existing account in the database linked to the API key. 
##[br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_DELETION_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
##[br][b]password -[/b] The password of the account.
func delete_account(email : String, password : String) -> int:
	return await _data_controller.delete_account(email, password)

##Can be used to verify the email of an account. Requires email verification to be enabled in the User Accounts 
##settings. An email can be verified by inputting the verification code sent to the email address. 
##Verifying the email will automatically log in the user. 
##[br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_VERIFICATION_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
##[br][b]code -[/b] The verification code that was sent to the email address.
##[br][b]valid_time -[/b] The time in seconds how long the login session is valid.
func verify_account(email : String, code : String, valid_time : float = 86400) -> int:
	return await _data_controller.verify_account(email, code, valid_time)

##Sends a new verification code to the email address. A new code can only be sent once the most recent 
##code has expired. Requires email verification to be enabled in the User Account settings.
##[br][br]Returns the result of the request as [constant ENUMS.RESEND_VERIFICATION_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
##[br][b]password -[/b] The password of the account.
func resend_verification_code(email : String, password : String) -> int:
	return await _data_controller.resend_verification_code(email, password)

##Returns if the specified account has a verified email. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.IS_VERIFIED_RESPONSE_CODE] response code. 
##[br]
##[br][b]username -[/b] The username of the account.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : true
##}[/codeblock]
func is_verified(username : String = "") -> Dictionary:
	return await _data_controller.is_verified(username)

##Attempt to login into an existing account. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.LOGIN_RESPONSE_CODE] response code. 
##[br]
##[br]
##If the user is banned, it will include the "Banned" key, which contains the unix timestamp when the ban will 
##expire. If the ban is permanent, the value will be -1. 
##[br]
##[br][b]email -[/b] The email of the account.
##[br][b]password -[/b] The password of the account.
##[br][b]valid_time -[/b] The time in seconds how long the login session is valid.
##[codeblock]
##{
##   "Code" : 0,
##   "BanTime" : 1719973379
##}[/codeblock]
func login(email : String, password : String, valid_time : float = 86400) -> Dictionary:
	return await _data_controller.login(email, password, valid_time)

##Attempt to login with a previous session. If that session has not yet expired it will login using 
##and refresh the session time. 
##[br][br]Returns the result of the request as [constant ENUMS.LOGIN_RESPONSE_CODE].
##[br]
##[br][b]valid_time -[/b] The time in seconds how long the login session is valid.
func login_from_session(valid_time : float = 86400) -> int:
	return await _data_controller.login_from_session(valid_time)

##Invalidates the current login session. 
##[br][br]Returns the result of the request as [constant ENUMS.LOGOUT_RESPONSE_CODE].
func logout() -> int:
	return await _data_controller.logout()

##Changes the username of the currently logged in account.
##[br][br]Returns the result of the request as [constant ENUMS.CHANGE_USERNAME_RESPONSE_CODE].
##[br]
##[br][b]new_username -[/b] The new username. The username has to be unique and between 3 and 20 characters long.
func change_account_username(new_username : String) -> int:
	return await _data_controller.change_username(new_username)

##Changes the password of an existing account.
##[br][br]Returns the result of the request as [constant ENUMS.CHANGE_PASSWORD_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
##[br][b]password -[/b] The current password of the account.
##[br][b]new_password -[/b] The new password of the account.
func change_account_password(email : String, password : String, new_password : String) -> int:
	return await _data_controller.change_password(email, password, new_password)

##Requests a password reset code for the specified account. The reset code will be sent to the email address.
##[br][br]Returns the result of the request as [constant ENUMS.REQUEST_PASSWORD_RESET_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
func request_account_password_reset(email : String) -> int:
	return await _data_controller.request_password_reset(email)

##Attempt to use a password reset code. If the code is valid the password of the account will be changed. 
##See [method request_account_password_reset] for sending the password reset code. 
##[br][br]Returns the result of the request as [constant ENUMS.RESET_PASSWORD_RESPONSE_CODE].
##[br]
##[br][b]email -[/b] The email of the account.
func reset_password(email : String, reset_code : String, new_password : String) -> int:
	return await _data_controller.reset_password(email, reset_code, new_password)

##Files a report against the specified account.
##[br][br]Returns the result of the request as [constant ENUMS.REPORT_USER_RESPONSE_CODE].
##[br]
##[br][b]username_to_report -[/b] The username of the account you want to report.
##[br][b]report -[/b] The report message. Has a maximum limit of 3000 characters.
func report_account(username_to_report : String, report : String) -> int:
	return await _data_controller.report_user(username_to_report, report)

##Store a dictionary/document of data on the currently logged-in account using GD-Sync cloud storage. The document 
##will be stored on the specified location. If the collections specified in the path don't already 
##exist, they are automatically created. Documents may also be nested in other documents.
##[br][br]Documents can be private or public. If externally visible, other players may retrieve and read 
##the document contents. Setting [param externally_visible] to true will automatically make all parent 
##collections/documents visible as well. Setting [param externally_visible] to false will automatically 
##hide all nested collections and documents.
##[br][br]Returns the result of the request as [constant ENUMS.SET_PLAYER_DOCUMENT_RESPONSE_CODE].
##[br]
##[br][b]path -[/b] The path where the document should be stored. An example path could be "saves/save1".
##[br][b]document -[/b] The data that you want to store in the cloud.
##[br][b]externally_visible -[/b] Decides if the document is public or private.
func set_player_document(path : String, document : Dictionary, externally_visible : bool = false) -> int:
	return await _data_controller.set_player_document(path, document, externally_visible)

##Documents can be private or public. If externally visible, other players may retrieve and read 
##the document contents. Setting [param externally_visible] to true will automatically make all parent 
##collections/documents visible as well. Setting [param externally_visible] to false will automatically 
##hide all nested collections and documents.
##[br][br]Returns the result of the request as [constant ENUMS.SET_EXTERNAL_VISIBLE_RESPONSE_CODE].
##[br]
##[br][b]path -[/b] The path of the document or collection.
##[br][b]externally_visible -[/b] Decides if the document is public or private.
func set_external_visible(path : String, externally_visible : bool = false) -> int:
	return await _data_controller.set_external_visible(path, externally_visible)

##Retrieve a dictionary/document of data from the currently logged-in account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.GET_PLAYER_DOCUMENT_RESPONSE_CODE] response code. 
##[br]
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : {<document>}
##}[/codeblock]
func get_player_document(path : String) -> Dictionary:
	return await _data_controller.get_player_document(path, "")

##Check if a dictionary/document or collection exists on the currently logged-in account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.HAS_PLAYER_DOCUMENT_RESPONSE_CODE] response code. 
##[br]
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : true
##}[/codeblock]
func has_player_document(path : String) -> Dictionary:
	return await _data_controller.has_player_document(path, "")

##Browse through a collection from the currently logged-in account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.BROWSE_PLAYER_COLLECTION_RESPONSE_CODE] response code. 
##[br]
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" :
##      [
##         {"ExternallyVisible": true, "Name": "profile", "Path": "saves/profile", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "save1", "Path": "saves/save1", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "save2", "Path": "saves/save2", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "configs", "Path": "saves/configs", "Type": "Collection"}
##      ]
##}[/codeblock]
func browse_player_collection(path : String) -> Dictionary:
	return await _data_controller.browse_player_collection(path, "")

##Delete a dictionary/document or collection from the currently logged-in account using GD-Sync cloud storage. 
##[br][br]Returns the result of the request as [constant ENUMS.DELETE_PLAYER_DOCUMENT_RESPONSE_CODE].
##[br]
##[br][b]path -[/b] The path of the document or collection.
func delete_player_document(path : String) -> int:
	return await _data_controller.delete_player_document(path)

##Retrieve a dictionary/document of data from another account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.GET_PLAYER_DOCUMENT_RESPONSE_CODE] response code. 
##[br]
##[br][b]external_username -[/b] The username of the account you want to perform the action on.
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : {<document>}
##}[/codeblock]
func get_external_player_document(external_username : String, path : String) -> Dictionary:
	return await _data_controller.get_player_document(path, external_username)

##Check if a dictionary/document or collection exists on another account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.HAS_PLAYER_DOCUMENT_RESPONSE_CODE] response code. 
##[br]
##[br][b]external_username -[/b] The username of the account you want to perform the action on.
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : true
##}[/codeblock]
func has_external_player_document(external_username : String, path : String) -> Dictionary:
	return await _data_controller.has_player_document(path, external_username)

##Browse through a collection from another account using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.BROWSE_PLAYER_COLLECTION_RESPONSE_CODE] response code. 
##[br]
##[br][b]external_username -[/b] The username of the account you want to perform the action on.
##[br][b]path -[/b] The path of the document or collection.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" :
##      [
##         {"ExternallyVisible": true, "Name": "profile", "Path": "saves/profile", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "save1", "Path": "saves/save1", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "save2", "Path": "saves/save2", "Type": "Document"},
##         {"ExternallyVisible": false, "Name": "configs", "Path": "saves/configs", "Type": "Collection"}
##      ]
##}[/codeblock]
func browse_external_player_collection(external_username : String, path : String) -> Dictionary:
	return await _data_controller.browse_player_collection(path, external_username)

##Check if a leaderboard exists using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.HAS_LEADERBOARD_RESPONSE_CODE] response code. 
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : true
##}[/codeblock]
func has_leaderboard(leaderboard : String) -> Dictionary:
	return await _data_controller.has_leaderboard(leaderboard)

##Retrieve a list of all leaderboards using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.GET_LEADERBOARDS_RESPONSE_CODE] response code. 
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : 
##      [
##         "Leaderboard1",
##         "Leaderboard2"
##      ]
##}[/codeblock]
func get_leaderboards() -> Dictionary:
	return await _data_controller.get_leaderboards()


##Browse a leaderboard and all submitted scores using GD-Sync cloud storage. 
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.BROWSE_LEADERBOARD_RESPONSE_CODE] response code. 
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
##[br][b]page_size -[/b] The amount of scores returned. The maximum page size is 100.
##[br][b]page -[/b] The page you want to retrieve. The first page is page 1.
##[codeblock]
##{
##   "Code" : 0,
##   "FinalPage": 7,
##   "Result" : 
##      [
##         {"Rank": 1, "Score": 828, "Username": "User1"},
##         {"Rank": 2, "Score": 700, "Username": "User2"},
##         {"Rank": 3, "Score": 10, "Username": "User3"}
##      ]
##}[/codeblock]
func browse_leaderboard(leaderboard : String, page_size : int, page : int) -> Dictionary:
	return await _data_controller.browse_leaderboard(leaderboard, page_size, page)

##Get the score and rank of an account for a specific leaderboard using GD-Sync cloud storage. 
##If the user has no score submission on the leaderboard, Score will be 0 and Rank -1.
##[br][br]Returns a [Dictionary] with the format seen below 
##and the [constant ENUMS.GET_LEADERBOARD_SCORE_RESPONSE_CODE] response code. 
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
##[br][b]page_size -[/b] The amount of scores returned. The maximum page size is 100.
##[codeblock]
##{
##   "Code" : 0,
##   "Result" : 
##      {
##         "Score" : 100,
##         "Rank" : 1
##      }
##}[/codeblock]
func get_leaderboard_score(leaderboard : String, username : String) -> Dictionary:
	return await _data_controller.get_leaderboard_score(leaderboard, username)

##Submits a score to a leaderboard for the currently logged-in account using GD-Sync cloud storage. 
##If the user already has a score submission, it will be overwritten.
##[br][br]Returns the result of the request as [constant ENUMS.SUBMIT_SCORE_RESPONSE_CODE].
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
##[br][b]score -[/b] The score you want to submit.
func submit_score(leaderboard : String, score : int) -> int:
	return await _data_controller.submit_score(leaderboard, score)

##Deletes a score from a leaderboard for the currently logged-in account using GD-Sync cloud storage. 
##[br][br]Returns the result of the request as [constant ENUMS.DELETE_SCORE_RESPONSE_CODE].
##[br]
##[br][b]leaderboard -[/b] The name of the leaderboard.
func delete_score(leaderboard : String) -> int:
	return await _data_controller.delete_score(leaderboard)
