extends Node
class_name MultiplayerClient

#Copyright (c) 2026 GD-Sync.
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
#region Signals

## Emitted when the plugin successfully completes the connection and encryption handshake.
## This signal is emitted after using [method start_multiplayer].
## If this is emitted it means you can use all other multiplayer functions.
signal connected()

## Emitted if the connection handshake failes. This signal is emitted after using [method start_multiplayer].
## [br]
## [br][b]error -[/b] The reason behind the failed connection attempt. See [constant ENUMS.CONNECTION_ERROR] for possible errors.
signal connection_failed(error : int)

## Emitted when the client disconnects. Might be due to connectivity issues or when the server goes down.
## [br]
## [br][b]IMPORTANT: The plugin does not automatically try to reconnect when a disconnect occurs.[/b]
signal disconnected()

## Emitted when the Client ID changes. This happens when using [method start_mutliplayer] and might happen
## when using [method lobby_join]. This will NEVER happen while inside a lobby, so don't worry when
## using methods such as [method set_gdsync_owner], [method call_func_on], etc.
signal client_id_changed(own_id : int)

## Emitted if [method lobby_create] was successful.
## [br]
## [br][b]lobby_name -[/b] The name of the lobby that was created.
signal lobby_created(lobby_name : String)

## Emitted if [method lobby_create] failes.
## [br]
## [br][b]lobby_name -[/b] The name of the lobby that failed to create.
## [br][b]error -[/b] The reason why the creation failed.
## Check [constant ENUMS.LOBBY_CREATION_ERROR] for possible errors.
signal lobby_creation_failed(lobby_name : String, error : int)

## Emitted if [method lobby_change_name] was successful.
## [br]
## [br][b]lobby_name -[/b] The new lobby name.
signal lobby_name_changed(lobby_name : String)

## Emitted if [method lobby_change_name] failes.
## [br]
## [br][b]lobby_name -[/b] The new lobby name that failed.
## [br][b]error -[/b] The reason why the name change failed.
## Check [constant ENUMS.LOBBY_NAME_CHANGE_ERROR] for possible errors.
signal lobby_name_change_failed(lobby_name : String, error : int)

## Emitted when [method lobby_join] was successful.
## [br]
## [br][b]lobby_name -[/b] The name of the lobby that the player joined.
signal lobby_joined(lobby_name : String)

## Emitted when [method lobby_join] failed.
## [br]
## [br][b]lobby_name -[/b] The name of the lobby that the player was unable to join.
## [br][b]error -[/b] The reason why the joining failed.
## Check [constant ENUMS.LOBBY_JOIN_ERROR] for possible errors.
signal lobby_join_failed(lobby_name : String, error : int)

## Emitted when any lobby data value is changed. Emitted after [method lobby_set_data].
## [br]
## [br][b]key -[/b] The key of the data that changed.
## [br][b]value -[/b] The new value. This will be null is the data was erased.
signal lobby_data_changed(key : String, value)

## Emitted when any lobby tags value is changed. Emitted after [method set_lobby_tags] and [method erase_lobby_tags].
## [br]
## [br][b]key -[/b] The key of the tag that changed.
## [br][b]value -[/b] The new value. This will be null is the tag was erased.
signal lobby_tag_changed(key : String, value)

## Emitted when a client joins the current lobby.
## [br][b]IMPORTANT: This is emitted for all clients, [color=light_green]INCLUDING[/color] yourself when joining a lobby.[/b]
## [br]
## [br][b]client_id -[/b] The id of the client that joined.
signal client_joined(client_id : int)

## Emitted when a client leaves the current lobby.
## [br][b]IMPORTANT: This is emitted for ALL clients, [color=crimson]EXCLUDING[/color] yourself when leaving a lobby.[/b]
## [br]
## [br][b]client_id -[/b] is the id of the client that left.
signal client_left(client_id : int)

## Emitted when a player uses [method player_set_data], [method player_erase_data] or [method player_set_username].
## Player data is synchronized every second if it is altered.
## [br]
## [br][b]client_id -[/b] is the id of the client that left.
signal player_data_changed(client_id : int, key : String, value)

## Emitted if you get kicked from the current lobby.
signal kicked()

## Emitted as a result of [method get_public_lobbies].
## [br]
## [br][b]lobbies -[/b] An array of all public lobbies and their publicly available data.
signal lobbies_received(lobbies : Array)

## Emitted as a result of [method get_public_lobby].
## [br]
## [br][b]lobby -[/b] A dictionary containing public lobby data. If the lobby was not found the dictionary will be empty.
signal lobby_received(lobby : Dictionary)

## Emitted when the host of the current lobby changes. This might happen if the current host leaves or disconnects.
## The server automatically decides which player is the host.
## [br]
## [br]Being the host does not do anything by itself, but is something that can help you when developing authorative code.
## [br]The [PropertySynchronizer] class will also make use of this if told to do so in the inspector.
## [br]
## [br][b]is_host -[/b] A boolean that indicates if you are the new host or not.
## [br][b]new_host_id -[/b] The Client ID of the new host.
signal host_changed(is_host : bool, new_host_id : int)

## Emitted when a time synchronized event is triggered. See [method synced_event_create] for more information.
## [br]
## [br][b]event_name -[/b] The name of the event that has been triggered.
## [br][b]parameters -[/b] Any parameters binded to the event.
signal synced_event_triggered(event_name : String, parameters : Array)

## Emitted when [method change_scene] is called.
## [br]
## [br][b]scene_path -[/b] The path of the scene.
signal change_scene_called(scene_path : String)

## Emitted right before the scene is switched when using [method change_scene]
## [br]
## [br][b]scene_path -[/b] The path of the scene.
signal change_scene_success(scene_path : String)

## Emitted when a scene change failed for any of the clients in the lobby.
## This can be because of an invalid path, failing to load the resource, etc.
## [br]
## [br][b]scene_path -[/b] The path of the scene.
signal change_scene_failed(scene_path : String)

## Emitted when the player tries to join a friend on Steam.
## [br]
## [br][b]lobby_name -[/b] The name of lobby the player is trying to join.
## [br][b]has_password -[/b] If the lobby has a password or not.
signal steam_join_request(lobby_name : String, has_password : bool)




#endregion
# Initialization --------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Initialization

var _request_processor
var _connection_controller
var _session_controller
var _https_controller
var _data_controller
var _node_tracker
var _local_server
var _steam
var _logger

func _init():
	_request_processor = preload("res://addons/GD-Sync/Scripts/RequestProcessor.gd").new()
	_connection_controller = preload("res://addons/GD-Sync/Scripts/ConnectionController.gd").new()
	_session_controller = preload("res://addons/GD-Sync/Scripts/SessionController.gd").new()
	_https_controller = preload("res://addons/GD-Sync/Scripts/HTTPSController.gd").new()
	_data_controller = preload("res://addons/GD-Sync/Scripts/DataController.gd").new()
	_node_tracker = preload("res://addons/GD-Sync/Scripts/NodeTracker.gd").new()
	_local_server = preload("res://addons/GD-Sync/Scripts/LocalServer.gd").new()
	_steam = preload("res://addons/GD-Sync/Scripts/Steam.gd").new()
	_logger = preload("res://addons/GD-Sync/Scripts/Logger.gd").new()

func _ready():
	add_child(_request_processor)
	add_child(_connection_controller)
	add_child(_session_controller)
	add_child(_https_controller)
	add_child(_data_controller)
	add_child(_node_tracker)
	add_child(_local_server)
	add_child(_steam)
	add_child(_logger)









#endregion
# General functions -----------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region General Functions

## Starts the GD-Sync plugin by connecting to a server. If successful, [signal connected] will be emitted.
## If not, [signal connection_failed] will be emitted.
func start_multiplayer() -> void:
	_connection_controller.start_multiplayer()

## An alternative for get_tree().quit(). Only use if you log into a GD-Sync account using [method account_login].
## When quiting while logged in the plugin makes some callbacks to the server to update information like
## your friend status.
func quit() -> void:
	_data_controller.quit()

## Starts the GD-Sync plugin locally. This will allow for local peer-to-peer connections but will disable features
## such as database access and automatic host switching. Local mode also disables some optimization features
## related to networking.
## Using local multiplayer does not require an account or API keys and does not use any data transfer.
## [br][br]If successful, [signal connected] will be emitted.
## If not, [signal connection_failed] will be emitted.
func start_local_multiplayer() -> void:
	_connection_controller.start_local_multiplayer()

## Stops the GD-Sync plugin. This will break any existing connections and disable the multiplayer.
func stop_multiplayer() -> void:
	_connection_controller.stop_multiplayer()

## Returns true if the plugin is connected to a server. Returns false if there is no active connection.
func is_active() -> bool:
	return _connection_controller.is_active()

func _manual_connect(address : String) -> void:
	_connection_controller.connect_to_server(address)

## Returns your own Client ID. Returns -1 if you are not connected to a server.
func get_client_id() -> int:
	return _connection_controller.client_id

## Measures and returns the ping between this client and another client. This only measures network travel time for the message. Useful for checking raw network latency between clients.
## If the returned float is -1, the ping calculation failed.
func get_client_ping(client_id : int) -> float:
	return await _session_controller.get_ping(client_id, true)

## Measures and returns the perceived ping between this client and another client. This includes network travel time plus additional delay caused by frame timing. Useful for estimating player-visible latency..
## If the returned float is -1, the ping calculation failed.
func get_client_percieved_ping(client_id : int) -> float:
	return await _session_controller.get_ping(client_id, false)

## Returns the Client ID of the last client to perform a remote function call on this client.
## Useful for knowing where a remote function call came from.
## Returns -1 if nobody performed a remote function call yet.
## [br]
## [br][b]IMPORTANT:[/b] For this function to work, make sure to enable it in the GD-Sync configuration menu.
func get_sender_id() -> int:
	return _session_controller.get_sender_id()

## Returns whether you are the host of the lobby you are in.
func is_host() -> bool:
	return _connection_controller.host == get_client_id()

## Returns the Client ID of the host of the current lobby you are in. Returns -1 if you are not in a lobby.
func get_host() -> int:
	return _connection_controller.host

## Manually sets the host of the current lobby. Can only be used by the current host. This function does not work in local multiplayer.
## [br]
## [br][b]client_id -[/b] The Client ID of the new host.
func set_host(client_id : int) -> void:
	_request_processor.create_set_host_request(client_id)

## Synchronizes a variable on a Object across all other clients in the current lobby.
## Make sure that the variable is exposed using [method expose_var] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]object -[/b] The Object you want to synchronize a variable on.
## [br][b]variable_name -[/b] The name of the variable you want to synchronize.
## [br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until successful.
## This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.
func sync_var(object : Object, variable_name : String, reliable : bool = true) -> void:
	_request_processor.create_set_var_request(object, variable_name, -1, reliable)

## Synchronizes a variable on a Object to a specific client in the current lobby.
## Make sure that the variable is exposed using [method expose_var] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]client_id -[/b] The Client ID of the client you want to synchronize to.
## [br][b]object -[/b] The Object you want to synchronize a variable on.
## [br][b]variable_name -[/b] The name of the variable you want to synchronize.
## [br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until successful.
## This may introduce more latency. Use unreliable if the sync happens frequently (such as the position of a Node) for lower latency.
func sync_var_on(client_id : int, object : Object, variable_name : String, reliable : bool = true) -> void:
	_request_processor.create_set_var_request(object, variable_name, client_id, reliable)

## Calls a function on a Node or Resource on all other clients in the current lobby, excluding yourself.
## Make sure that the function is exposed using [method expose_func] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]callable -[/b] The function that you want to call.
## [br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
## [br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until successful.
## This may introduce more latency. Use unreliable if the function call is non-essential.
func call_func(callable : Callable, parameters : Array = [], reliable : bool = true) -> void:
	_request_processor.create_function_call_request(callable, parameters, -1, reliable)

## Calls a function on a Node or Resource on a specific client in the current lobby.
## Make sure that the function is exposed using [method expose_func] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]client_id -[/b] The Client ID of the client you want to call the function on.
## [br][b]callable -[/b] The function that you want to call.
## [br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
## [br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until successful.
## This may introduce more latency. Use unreliable if the function call is non-essential.
func call_func_on(client_id : int, callable : Callable, parameters : Array = [], reliable  : bool = true) -> void:
	_request_processor.create_function_call_request(callable, parameters, client_id, reliable)

## Calls a function on a Node or Resource on all clients in the current lobby, including yourself.
## Make sure that the function is exposed using [method expose_func] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]callable -[/b] The function that you want to call.
## [br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
## [br][b]reliable -[/b] If reliable, if the request fails to deliver it will reattempt until successful.
## This may introduce more latency. Use unreliable if the function call is non-essential.
func call_func_all(callable : Callable, parameters : Array = [], reliable : bool = true) -> void:
	callable.callv(parameters)
	_request_processor.create_function_call_request(callable, parameters, -1, reliable)

## Emits a signal on a Node or Resource on all other clients in the current lobby, excluding yourself.
## Make sure that the signal is exposed using [method expose_signal] or [method expose_node]/[method expose_resource].
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]object -[/b] The object on which you want to emit the signal.
## [br][b]signal_name -[/b] The name of the signal.
## [br][b]parameters -[/b] Optional parameters. Parameters must be passed in an array, [12, "Woohoo!"].
func emit_signal_remote(target_signal : Signal, parameters : Array = []) -> void:
	var clients : Array = lobby_get_all_clients()
	clients.erase(get_client_id())
	_session_controller.emit_signal_on_clients(clients, target_signal, parameters)

func emit_signal_remote_on(client_id : int, target_signal : Signal, parameters : Array = []) -> void:
	_session_controller.emit_signal_on_clients([client_id], target_signal, parameters)

func emit_signal_remote_all(target_signal : Signal, parameters : Array = []) -> void:
	var clients : Array = lobby_get_all_clients()
	_session_controller.emit_signal_on_clients(clients, target_signal, parameters)

## Instantiates a Node on all clients in the current lobby.
## [br]
## [br][b]IMPORTANT:[/b] Make sure the NodePath of the parent matches up on all clients.
## [br]
## [br][b]scene -[/b] The [PackedScene] you want to instantiate.
## [br][b]parent -[/b] The parent/location of where you want to instantiate the Node.
## [br][b]sync_starting_changes -[/b] If enabled, any changes made to the root Node of the instantiated scene
## within the same frame will automatically be synchronized.
## [br][b]excluded_properties -[/b] Names of properties you want to exclude from sync_starting_changes.
## [br][b]replicate_on_join -[/b] If enabled, the instantiated Node will be replicated on clients that
## join the lobby later on.
func multiplayer_instantiate(
		scene : PackedScene,
		parent : Node,
		sync_starting_changes : bool = true,
		excluded_properties : PackedStringArray = [],
		replicate_on_join : bool = true) -> Node:
	return _node_tracker.multiplayer_instantiate(scene, parent, sync_starting_changes, excluded_properties, replicate_on_join)

func multiplayer_queue_free(node : Node) -> void:
	_node_tracker.multiplayer_queue_free(node)

## Returns a float which contains the current multiplayer time. This time is synchronized across clients in
## the same lobby. Can be used for time-based events. See [method synced_event_create] for creating
## time-based triggers.
## [br]
## [br][b]IMPORTANT:[/b] It may take up to a second for the time to synchronize after just joining a lobby.
func get_multiplayer_time() -> float:
	return _session_controller.synced_time

## Create a time-based event that triggers after a delay. GD-Sync will attempt to trigger this event
## on all clients at the same time, regardless of the latency between clients. Useful for creating
## time-critical events or mechanics. After the delay, [signal synced_event_triggered] is emitted.
## [br]
## [br][b]IMPORTANT:[/b] If the given delay is shorter than the latency between two clients, the
## event trigger might be delayed. It is recommended to always use a delay >= 1 second.
## [br]
## [br][b]event_name -[/b] The name of the event. Queued events can share the same name.
## [br][b]delay -[/b] The delay in seconds after which the event should be triggered.
## [br][b]parameters -[/b] Any parameters which should be binded to the event.
func synced_event_create(event_name : String, delay : float = 1.0, parameters : Array = []) -> void:
	_session_controller.register_event(event_name, get_multiplayer_time()+delay, parameters, true)

## Changes the current scene for all clients. Waits with changing until the scene has fully loaded on all clients.
## Emits [code]change_scene_called[/code] when a scene change is requested, [code]change_scene_success[/code] when it succeeds,
## and [code]change_scene_failed[/code] if it fails on any client.
## [br]
## [br][b]scene_path -[/b] The resource path of the scene.
func change_scene(scene_path : String) -> void:
	_session_controller.change_scene(scene_path)







#endregion
# Security & safety functions -------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Security & safety functions

## If set to true, all remote function calls and variable synchronization requests will be blocked by default.
## Only functions, variables and Nodes that are exposed using [method expose_func], [method expose_var] and [expose_node]
## may be accessed remotely. This setting can also be found in the configuration menu.
## [br]
## [br]
## We STRONGLY recommendd keeping this enabled at all times. Disabling it may introduce security risks.
## [br]
## [br][b]protected -[/b] If protected mode should be enabled or disabled.
func set_protection_mode(protected : bool) -> void:
	_request_processor.set_protection_mode(protected)

## Allows you to register a resource with a unique ID so that GD-Sync may access it remotely.
## [br]
## [br][b]resource -[/b] The resource you want to register.
## [br][b]id -[/b] The ID you want to assign to it.
func register_resource(resource : RefCounted, id : String) -> void:
	_session_controller.create_resource_reference(resource, id)

## Allows you to deregister a previously registered resource.
## [br]
## [br][b]resource -[/b] The resource you want to deregister.
func deregister_resource(resource : RefCounted) -> void:
	_session_controller.erase_resource_reference(resource)

## Exposes a Node so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will succeed.
## Only use if the Node and its script contain non-destructive functions.
## [br]
## [br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients.
## [br]
## [br][b]node -[/b] The Node you want to expose.
func expose_node(node : Node) -> void:
	_session_controller.expose_object(node)

## Hides a Node so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will fail.
## This will not revert [method expose_func] and [method expose_var].
## [br]
## [br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients.
## [br]
## [br][b]node -[/b] The Node you want to hide.
func hide_node(node : Node) -> void:
	_session_controller.hide_object(node)

## Exposes a Resource so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will succeed.
## Only use if the Resource and its script contain non-destructive functions.
## [br]
## [br][b]IMPORTANT:[/b] Make sure the Resource has been registered using [method register_resource].
## [br]
## [br][b]resource -[/b] The Resource you want to expose.
func expose_resource(resource : RefCounted) -> void:
	_session_controller.expose_object(resource)

## Hides a Resource so that all [method call_func], [method call_func_on], [method sync_var] and [method sync_var_on] will fail.
## This will not revert [method expose_func] and [method expose_var].
## [br]
## [br][b]IMPORTANT:[/b] Make sure the Resource has been registered using [method register_resource].
## [br]
## [br][b]resource -[/b] The Resource you want to hide.
func hide_resource(resource : RefCounted) -> void:
	_session_controller.hide_object(resource)

## Exposes a function so that [method call_func] and [method call_func_on] will succeed.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]callable -[/b] The function you want to expose.
func expose_func(callable : Callable) -> void:
	_session_controller.expose_func(callable)

## Hides a function so that [method call_func] and [method call_func_on] will fail.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]callable -[/b] The function you want to hide.
func hide_func(callable : Callable) -> void:
	_session_controller.hide_func(callable)

## Exposes a signal so that [method emit_signal_remote], [method emit_signal_remote_on] and [method emit_signal_remote_all] will succeed.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]signal_name -[/b] The signal you want to expose.
func expose_signal(target_signal : Signal) -> void:
	_session_controller.expose_signal(target_signal)

## Hides a signal so that [method emit_signal_remote], [method emit_signal_remote_on] and [method emit_signal_remote_all] will fail.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]signal_name -[/b] The signal you want to hide.
func hide_signal(target_signal : Signal) -> void:
	_session_controller.hide_signal(target_signal)

## Exposes a variable so that [method sync_var] and [method sync_var_on] will succeed.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]object -[/b] The Object on which you want to expose the variable.
## [br][b]variable_name -[/b] The name of the variable you want to expose.
func expose_var(object : Object, variable_name : String) -> void:
	_session_controller.expose_property(object, variable_name)

## Hides a variable so that [method sync_var] and [method sync_var_on] will fail.
## [br]
## [br][b]IMPORTANT:[/b] For Nodes, make sure the NodePath of the Node matches up on all clients. For Resources, register them using [method register_resource].
## [br]
## [br][b]object -[/b] The Object on which you want to hide the variable.
## [br][b]variable_name -[/b] The name of the variable you want to hide.
func hide_var(object : Object, variable_name : String) -> void:
	_session_controller.hide_property(object, variable_name)









#endregion
# Node Ownership --------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Node Ownership

## Sets the owner of a Node. Node ownership is recursive and will apply to all children.
## Being the owner of a Node does not do anything by itself, but is useful when writing certain scripts.
## For example, when you are re-using your player scene for all players, you can only execute the keyboard inputs on
## the player of which you are the owner.
## [br]The [PropertySynchronizer] class will also make use of this if told to do so in the inspector.
## [br]
## [br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients.
## [br]
## [br][b]node -[/b] The Node on which you want to assign ownership to.
## [br][b]owner -[/b] The client ID of the new owner.
func set_gdsync_owner(node : Node, owner : int) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_gdsync_owner(node, owner)

## Clears the owner of a Node. Node ownership is recursive and will be removed on all children.
## [br]
## [br][b]IMPORTANT:[/b] Make sure the NodePath of the Node matches up on all clients.
## [br]
## [br][b]node -[/b] The Node on which you want to clear ownership.
func clear_gdsync_owner(node : Node) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_gdsync_owner(node, -1)

## Returns the Client ID of the client that has ownership of the Node. Returns -1 if there is no owner.
## [br]
## [br][b]node -[/b] The Node from which you want to retrieve the owner.
func get_gdsync_owner(node : Node) -> int:
	return _session_controller.get_gdsync_owner(node)

## Returns true if you are the owner of the Node in question. Returns false if you are not the owner or when there is not owner.
## [br]
## [br][b]node -[/b] The Node on which you want to perform the ownership check.
func is_gdsync_owner(node : Node) -> bool:
	return _session_controller.is_gdsync_owner(node)

## Connects up a signal so that a specific function gets called if the owner of the Node changes.
## The function must have one parameter which is the Client ID of the new owner.
## The Client ID will be -1 if the doesn't have an owner anymore
## [br]
## [br][b]node -[/b] The Node of which you want to monitor ownership.
## [br][b]callable -[/b] The function that should get called if the owner changes.
func connect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	_session_controller.connect_gdsync_owner_changed(node, callable)


## Disconnects a function from the ownership signal created in [method connect_gdsync_owner_changed].
## [br]
## [br][b]node -[/b] The Node of which you want to disconnect ownership monitoring.
## [br][b]callable -[/b] The function that should get disconnected.
func disconnect_gdsync_owner_changed(node : Node, callable : Callable) -> void:
	_session_controller.disconnect_gdsync_owner_changed(node, callable)









#endregion
# Lobby Functions -------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Lobby Functions

## Attempts to retrieve all publicly visible lobbies from the server.
## Will emit the signal [signal lobbies_received] once the server has collected all lobbies
func get_public_lobbies() -> void:
	if !_connection_controller.valid_connection(): return
	if _connection_controller.is_local():
		_local_server.get_public_lobbies()
	else:
		_request_processor.get_public_lobbies()

## Attempts to retrieve a publicly visible lobby from the server.
## Will emit the signal [signal lobby_received] once the server has collected the lobby information
## [br]
## [br][b]lobby_name -[/b] The name of the lobby.
func get_public_lobby(lobby_name : String) -> void:
	if !_connection_controller.valid_connection(): return
	if _connection_controller.is_local():
		_local_server.get_public_lobby(lobby_name)
	else:
		_request_processor.get_public_lobby(lobby_name)

## Attempts to create a lobby on the server. If successful [signal lobby_created] is emitted.
## If it fails [signal lobby_creation_failed] is emitted. Creating a lobby has a cooldown of 3 seconds.
## [br]
## [br][b]name -[/b] The name of the lobby you want to create. Has a maximum of 32 characters.
## [br][b]password -[/b] The password of the lobby. Leave empty if you want everyone to be able to join without a password.
## Has a maximum of 16 characters.
## [br][b]public -[/b] If true, the lobby will be visible when using [method get_public_lobbies]
## [br][b]player_limit -[/b] The player limit of the lobby. If 0 it will automatically be set to the maximum your plan allows.
## This is also the case if the limit entered exceeds your plan limit.
## [br][b]tags -[/b] Any starting tags you would like to add to the lobby.
## [br][b]data -[/b] Any starting data you would like to add to the lobby.
func lobby_create(name : String, password : String = "", public : bool = true, player_limit : int = 0, tags : Dictionary = {}, data : Dictionary = {}) -> void:
	if !_connection_controller.valid_connection(): return
	if _connection_controller.is_local():
		_local_server.create_local_lobby(name, password, public, player_limit, tags, data)
	else:
		_request_processor.create_new_lobby_request(name, password, public, player_limit, tags, data)

## Attempts to join an existing lobby. If successful [signal lobby_joined] is emitted.
## If it fails [signal lobby_join_failed] is emitted.
## Using this function might cause your Client ID to change when joining a lobby that is not on your current server.
## [br]
## [br][b]name -[/b] The name of the lobby you are trying to join.
## [br][b]password -[/b] The password of the lobby you are trying to join.
## If the lobby has no password this can have any value.
func lobby_join(name : String, password : String = "") -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_lobby_data(name, password)
	if _connection_controller.is_local():
		_local_server.join_lobby(name, password)
	else:
		_request_processor.create_join_lobby_request(name, password)

## Closes the lobby you are currently in, blocking any new players from joining. The lobby will still be visible when using [method get_public_lobbies].
func lobby_close() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_close_lobby_request()

## Opens the lobby you are currently in, allowing new players to join.
func lobby_open() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_open_lobby_request()

## Sets the visibility of the lobby you are currently in. Decides whether the lobby shows up when using [method get_public_lobbies]
## [br]
## [br][b]public -[/b] If the lobby should be visible or not.
func lobby_set_visibility(public : bool) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_lobby_visiblity_request(public)

## Changes the name of the current lobby. Only works for the host of the lobby. If successful [signal lobby_name_changed] is emitted.
## If it fails [signal lobby_name_change_failed] is emitted. Changing the lobby name shares a 3 second cooldown with [method lobby_create].
## [br]
## [br][b]name -[/b] The new lobby name. Has a maximum of 32 characters.
func lobby_change_name(name : String) -> void:
	_request_processor.create_lobby_name_change_request(name)

## Changes the password of the lobby. Only works for the host of the lobby.
## [br]
## [br][b]password -[/b] The new password of the lobby.
func lobby_change_password(password : String) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_change_lobby_password_request(password)

## Leaves the lobby you are currently in. This does not emit any signals.
func lobby_leave() -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_leave_lobby_request()
	_data_controller.set_friend_status()
	_session_controller.lobby_left()
	_node_tracker.lobby_left()
	_steam.leave_steam_lobby()

## Kicks a client from the current lobby. Only works for the host of the lobby.
## [br]
## [br][b]client_id -[/b] The ID of the client you want to kick.
func lobby_kick_client(client_id : int) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.kick_player(client_id)

## Returns the client IDs of all clients in the current lobby.
func lobby_get_all_clients() -> Array:
	return _session_controller.get_all_clients()

## Returns the amount of players in the current lobby.
func lobby_get_player_count() -> int:
	return _session_controller.get_all_clients().size()

## Get the current lobby name
func lobby_get_name() -> String:
	return GDSync._session_controller.lobby_name

## Get the current lobby visibility. Returns true if the lobby is publicly visible.
func lobby_get_visibility() -> bool:
	return _session_controller.get_lobby_visibility()

## Returns the player limit of the current lobby.
func lobby_get_player_limit() -> int:
	return _session_controller.get_lobby_player_limit()

## Returns true if the current lobby has a password.
func lobby_has_password() -> bool:
	return _session_controller.lobby_has_password()

## Adds a new or updates the value of a tag. Tags are publicly visible data that is returned with [method get_public_lobbies].
## Especially useful when display information like the gamemode or map.
## [br]
## [br]
## This does not instantly update, so it won't have an affect on [method lobby_has_tag] and [method lobby_get_tag] until
## a response from the server is returned. If the operation was successful [signal lobby_tag_changed] is emitted.
## [br]
## [br][b]key -[/b] The key of the tag.
## [br][b]value -[/b] The value of the tag that should be stored.
func lobby_set_tag(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_set_lobby_tag_request(key, value)

## Deletes an existing tag.
## [br]
## [br]
## This does not instantly update, so it won't have an affect on [method lobby_has_tag] and [method lobby_get_tag] until
## a response from the server is returned. If the operation was successful [signal lobby_tag_changed] is emitted.
## [br]
## [br][b]key -[/b] The key of the tag.
func lobby_erase_tag(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_erase_lobby_tag_request(key)

## Returns true if a tag with the given key exists.
## [br]
## [br][b]key -[/b] The key of the tag.
func lobby_has_tag(key : String) -> bool:
	return _session_controller.has_lobby_tag(key)

## Gets the value of a lobby tag.
## [br]
## [br][b]key -[/b] The key of the tag.
## [br][b]default -[/b] The default value that is returned if the given key does not exist.
func lobby_get_tag(key : String, default = null):
	return _session_controller.get_lobby_tag(key, default)

## Returns a dictionary with all lobby tags and their values.
func lobby_get_all_tags() -> Dictionary:
	return _session_controller.get_all_lobby_tags()

## Adds new or updates existing lobby data. Data is private data that can only be viewed from inside the lobby.
## [br]
## [br]
## This does not instantly update, so it won't have an affect on [method lobby_has_data] and [method lobby_get_data] until
## a response from the server is returned. If operation was successful [signal lobby_data_changed] is emitted.
## [br]
## [br][b]key -[/b] The key of the data.
## [br][b]value -[/b] The value of the data that should be stored.
func lobby_set_data(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_set_lobby_data_request(key, value)

## Deletes existing data.
## [br]
## [br]
## This does not instantly update, so it won't have an affect on [method lobby_has_data] and [method lobby_get_data] until
## a response from the server is returned. If operation was successful [signal lobby_data_changed] is emitted.
## [br]
## [br][b]key -[/b] The key of the tag.
func lobby_erase_data(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_request_processor.create_erase_lobby_data_request(key)

## Returns true if data with the given key exists.
## [br]
## [br][b]key -[/b] The key of the data.
func lobby_has_data(key : String) -> bool:
	return _session_controller.has_lobby_data(key)

## Gets the value of lobby data.
## [br]
## [br][b]key -[/b] The key of the data.
## [br][b]default -[/b] The default value that is returned if the given key does not exist.
func lobby_get_data(key : String, default = null):
	return _session_controller.get_lobby_data(key, default)

## Returns a dictionary with all lobby data and their values.
func lobby_get_all_data() -> Dictionary:
	return _session_controller.get_all_lobby_data()







#endregion
# Player Functions ------------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Player Functions

## Sets data for your client. Player data has a maximum size of 2048 bytes, if this limit is exceeded
## a critical error is printed.
## Emits [signal player_data_changed]. It may take up to 1 second for this signal to be emitted, as player
## data is synchronized every second if altered.
## [br]
## [br][b]key -[/b] The key of the player data.
## [br][b]value -[/b] The value of the player data.
func player_set_data(key : String, value) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.set_player_data(key, value)
	_request_processor.create_set_player_data_request(key, value)

## Erases data for your client.
## Emits [signal player_data_changed] with null as the value.
## [br]
## [br][b]key -[/b] The key of the player data.
func player_erase_data(key : String) -> void:
	if !_connection_controller.valid_connection(): return
	_session_controller.erase_player_data(key)
	_request_processor.create_erase_player_data_request(key)

## Gets data from a specific client. If you want to retreive your own data you can input your own id.
## You can get your own id using [method get_client_id].
## [br]
## [br][b]client_id -[/b] The Client ID of which client you would like to get the data from.
## [br][b]key -[/b] The key of the player data.
## [br][b]default -[/b] The default value that is returned if the given key does not exist.
func player_get_data(client_id : int, key : String, default = null):
	if !_connection_controller.valid_connection(): return default
	return _session_controller.get_player_data(client_id, key, default)

## Gets all data from a specific client. If you want to retreive your own data you can input your own id.
## You can get your own id using [method get_client_id].
## [br]
## [br][b]client_id -[/b] The Client ID of which client you would like to get the data from.
func player_get_all_data(client_id : int) -> Dictionary:
	if !_connection_controller.valid_connection(): return {}
	return _session_controller.get_all_player_data(client_id)

## Sets the username of the player. If enabled in the configuration menu, usernames can be set to unique.
## When this setting is enabled there can be no duplicate usernames inside a lobby.
## Emits [signal player_data_changed] with the key "Username".
## [br]
## [br][b]name -[/b] The username of this client.
func player_set_username(name : String) -> void:
	_request_processor.create_set_username_request(name)
	_session_controller.set_player_data("Username", name)

## Gets the username of the player with the given client ID. By default uses the ID of the local player.
## [br]
## [br][b]client_id -[/b] The ID of this client.
## [br][b]default -[/b] The default value to return if the username was not found.
func player_get_username(client_id : int = get_client_id(), default := "") -> String:
	if !_connection_controller.valid_connection(): return default
	return _session_controller.get_player_data(client_id, "Username", default)




#endregion
# Accounts & Persistent Data Storage ------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Accounts & Persistent Data Storage

## Creates an account in the database linked to the API key.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_CREATION_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account. The email has to be unique.
## [br][b]username -[/b] The username of the account. The username has to be unique.
## The username has to be between 3 and 20 characters long.
## [br][b]password -[/b] The password of the account.
## The password has to be between 3 and 20 characters long.
func account_create(email : String, username : String, password : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.create_account(email, username, password)

## Deletes an existing account in the database linked to the API key.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_DELETION_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
## [br][b]password -[/b] The password of the account.
func account_delete(email : String, password : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.delete_account(email, password)

## Can be used to verify the email of an account. Requires email verification to be enabled in the User Accounts
## settings. An email can be verified by inputting the verification code sent to the email address.
## Verifying the email will automatically log in the user.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_VERIFICATION_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
## [br][b]code -[/b] The verification code that was sent to the email address.
## [br][b]valid_time -[/b] The time in seconds how long the login session is valid.
func account_verify(email : String, code : String, valid_time : float = 86400) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.verify_account(email, code, valid_time)

## Sends a new verification code to the email address. A new code can only be sent once the most recent
## code has expired. Requires email verification to be enabled in the User Account settings.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_RESEND_VERIFICATION_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
## [br][b]password -[/b] The password of the account.
func account_resend_verification_code(email : String, password : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.resend_verification_code(email, password)

## Returns if the specified account has a verified email.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_IS_VERIFIED_RESPONSE_CODE] response code.
## [br]
## [br][b]username -[/b] The username of the account.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : true
## }[/codeblock]
func account_is_verified(username : String = "") -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.is_verified(username)

## Attempt to login into an existing account.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE] response code.
## [br]
## [br]
## If the user is banned, it will include the "Banned" key, which contains the unix timestamp when the ban will
## expire. If the ban is permanent, the value will be -1.
## [br]
## [br][b]email -[/b] The email of the account.
## [br][b]password -[/b] The password of the account.
## [br][b]valid_time -[/b] The time in seconds how long the login session is valid.
## [codeblock]
## {
##    "Code" : 0,
##    "BanTime" : 1719973379
## }[/codeblock]
func account_login(email : String, password : String, valid_time : float = 86400) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.login(email, password, valid_time)

## Attempt to login with a previous session. If that session has not yet expired it will login using
## and refresh the session time.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_LOGIN_RESPONSE_CODE].
## [br]
## [br][b]valid_time -[/b] The time in seconds how long the login session is valid.
func account_login_from_session(valid_time : float = 86400) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.login_from_session(valid_time)

## Invalidates the current login session.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_LOGOUT_RESPONSE_CODE].
func account_logout() -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.logout()

## Bans the current logged-in account.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_BAN_RESPONSE_CODE].
## [br]
## [br][b]ban_duration -[/b] The ban duration in days. Any amount above 1000 days results in a permanent ban.
func account_ban(ban_duration : float) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.ban_account(ban_duration)

## Changes the username of the currently logged in account.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_CHANGE_USERNAME_RESPONSE_CODE].
## [br]
## [br][b]new_username -[/b] The new username. The username has to be unique and between 3 and 20 characters long.
func account_change_username(new_username : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.change_username(new_username)

## Changes the password of an existing account.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_CHANGE_PASSWORD_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
## [br][b]password -[/b] The current password of the account.
## [br][b]new_password -[/b] The new password of the account.
func account_change_password(email : String, password : String, new_password : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.change_password(email, password, new_password)

## Requests a password reset code for the specified account. The reset code will be sent to the email address.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_REQUEST_PASSWORD_RESET_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
func account_request_password_reset(email : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.request_password_reset(email)

## Attempt to use a password reset code. If the code is valid the password of the account will be changed.
## See [method account_request_password_reset] for sending the password reset code.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_RESET_PASSWORD_RESPONSE_CODE].
## [br]
## [br][b]email -[/b] The email of the account.
func account_reset_password(email : String, reset_code : String, new_password : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.reset_password(email, reset_code, new_password)

## Files a report against the specified account.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_CREATE_REPORT_RESPONSE_CODE].
## [br]
## [br][b]username_to_report -[/b] The username of the account you want to report.
## [br][b]report -[/b] The report message. Has a maximum limit of 3000 characters.
func account_create_report(username_to_report : String, report : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.report_user(username_to_report, report)

## Sends a friend request to another account.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_SEND_FRIEND_REQUEST_RESPONSE_CODE].
## [br]
## [br][b]friend -[/b] The username of the account you want to send the friend request to.
func account_send_friend_request(friend : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.send_friend_request(friend)

## Accepts a friend request from another account
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_ACCEPT_FRIEND_REQUEST_RESPONSE_CODE].
## [br]
## [br][b]friend -[/b] The username of the account you want to accept the friend request from.
func account_accept_friend_request(friend : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.accept_friend_request(friend)

## Removes a friend. Also used to deny incoming friend requests.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_REMOVE_FRIEND_RESPONSE_CODE].
## [br]
## [br][b]friend -[/b] The username of the friend you want to remove.
func account_remove_friend(friend : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.remove_friend(friend)

## Gets the friend status between you and another account. Information besides the FriendStatus is only
## available if the friend request is accepted.
## If the lobby name is not empty, the player is in a lobby.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_GET_FRIEND_STATUS_RESPONSE_CODE] response code.
## [br]
## [br][b]friend -[/b] The username of the account you want the friend status of.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : {
##       "FriendStatus" : 2,
##       "Lobby" : {
##          "Name" : "Epic Lobby",
##          "HasPassword" : false
##       }
##    }
## }[/codeblock]
func account_get_friend_status(friend : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_friend_status(friend)

## Returns an array of all friends with their status. Information besides the FriendStatus is only
## available if the friend request is accepted.
## If the lobby name is not empty, the player is in a lobby.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_GET_FRIENDS_RESPONSE_CODE] response code.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : {
##       [
##          {
##             "Username" : "Epic Username",
##             "FriendStatus" : 2,
##             "Lobby" : {
##                "Name" : "Epic Lobby",
##                "HasPassword" : true
##             }
##          },
##          {
##             "Username" : "Cool Username",
##             "FriendStatus" : 2,
##             "Lobby" : {
##                "Name" : "",
##                "HasPassword" : false
##             }
##          },
##          {
##             "Username" : "Awesome Username",
##             "FriendStatus" : 1
##          }
##       ]
##    }
## }[/codeblock]
func account_get_friends() -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_friends()

## Store a dictionary/document of data on the currently logged-in account using GD-Sync cloud storage. The document
## will be stored on the specified location. If the collections specified in the path don't already
## exist, they are automatically created. Documents may also be nested in other documents.
## [br][br]Documents can be private or public. If externally visible, other players may retrieve and read
## the document contents. Setting [param externally_visible] to true will automatically make all parent
## collections/documents visible as well. Setting [param externally_visible] to false will automatically
## hide all nested collections and documents.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_DOCUMENT_SET_RESPONSE_CODE].
## [br]
## [br][b]path -[/b] The path where the document should be stored. An example path could be "saves/save1".
## [br][b]document -[/b] The data that you want to store in the cloud.
## [br][b]externally_visible -[/b] Decides if the document is public or private.
func account_document_set(path : String, document : Dictionary, externally_visible : bool = false) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.set_player_document(path, document, externally_visible)

## Documents can be private or public. If externally visible, other players may retrieve and read
## the document contents. Setting [param externally_visible] to true will automatically make all parent
## collections/documents visible as well. Setting [param externally_visible] to false will automatically
## hide all nested collections and documents.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_DOCUMENT_SET_EXTERNAL_VISIBLE_RESPONSE_CODE].
## [br]
## [br][b]path -[/b] The path of the document or collection.
## [br][b]externally_visible -[/b] Decides if the document is public or private.
func account_document_set_external_visible(path : String, externally_visible : bool = false) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.set_external_visible(path, externally_visible)

## Retrieve a dictionary/document of data from the currently logged-in account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_GET_DOCUMENT_RESPONSE_CODE] response code.
## [br]
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : {<document>}
## }[/codeblock]
func account_get_document(path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_player_document(path, "")

## Check if a dictionary/document or collection exists on the currently logged-in account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_HAS_DOCUMENT_RESPONSE_CODE] response code.
## [br]
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : true
## }[/codeblock]
func account_has_document(path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.has_player_document(path, "")

## Browse through a collection from the currently logged-in account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_BROWSE_COLLECTION_RESPONSE_CODE] response code.
## [br]
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" :
##       [
##          {"ExternallyVisible" : true, "Name" : "profile", "Path" : "saves/profile", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "save1", "Path" : "saves/save1", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "save2", "Path" : "saves/save2", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "configs", "Path" : "saves/configs", "Type" : "Collection"}
##       ]
## }[/codeblock]
func account_browse_collection(path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.browse_player_collection(path, "")

## Delete a dictionary/document or collection from the currently logged-in account using GD-Sync cloud storage.
## [br][br]Returns the result of the request as [constant ENUMS.ACCOUNT_DELETE_DOCUMENT_RESPONSE_CODE].
## [br]
## [br][b]path -[/b] The path of the document or collection.
func account_delete_document(path : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.delete_player_document(path)

## Retrieve a dictionary/document of data from another account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_GET_DOCUMENT_RESPONSE_CODE] response code.
## [br]
## [br][b]external_username -[/b] The username of the account you want to perform the action on.
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : {<document>}
## }[/codeblock]
func account_get_external_document(external_username : String, path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_player_document(path, external_username)

## Check if a dictionary/document or collection exists on another account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_HAS_DOCUMENT_RESPONSE_CODE] response code.
## [br]
## [br][b]external_username -[/b] The username of the account you want to perform the action on.
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : true
## }[/codeblock]
func account_has_external_document(external_username : String, path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.has_player_document(path, external_username)

## Browse through a collection from another account using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.ACCOUNT_BROWSE_COLLECTION_RESPONSE_CODE] response code.
## [br]
## [br][b]external_username -[/b] The username of the account you want to perform the action on.
## [br][b]path -[/b] The path of the document or collection.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" :
##       [
##          {"ExternallyVisible" : true, "Name" : "profile", "Path" : "saves/profile", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "save1", "Path" : "saves/save1", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "save2", "Path" : "saves/save2", "Type" : "Document"},
##          {"ExternallyVisible" : false, "Name" : "configs", "Path" : "saves/configs", "Type" : "Collection"}
##       ]
## }[/codeblock]
func account_browse_external_collection(external_username : String, path : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.browse_player_collection(path, external_username)

## Check if a leaderboard exists using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.LEADERBOARD_EXISTS_RESPONSE_CODE] response code.
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" : true
## }[/codeblock]
func leaderboard_exists(leaderboard : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.has_leaderboard(leaderboard)

## Retrieve a list of all leaderboards using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.LEADERBOARD_GET_ALL_RESPONSE_CODE] response code.
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" :
##       [
##          "Leaderboard1",
##          "Leaderboard2"
##       ]
## }[/codeblock]
func leaderboard_get_all() -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_leaderboards()


## Browse a leaderboard and all submitted scores using GD-Sync cloud storage.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.LEADERBOARD_BROWSE_SCORES_RESPONSE_CODE] response code.
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
## [br][b]page_size -[/b] The amount of scores returned. The maximum page size is 100.
## [br][b]page -[/b] The page you want to retrieve. The first page is page 1.
## [codeblock]
## {
##    "Code" : 0,
##    "FinalPage" : 7,
##    "Result" :
##       [
##          {"Rank" : 1, "Score" : 828, "Username" : "User1", "Data" : {"CustomValue" : 1},
##          {"Rank" : 2, "Score" : 700, "Username" : "User2"}, "Data" : {},
##          {"Rank" : 3, "Score" : 10, "Username" : "User3", "Data" : {}}
##       ]
## }[/codeblock]
func leaderboard_browse_scores(leaderboard : String, page_size : int, page : int) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.browse_leaderboard(leaderboard, page_size, page)

## Get the score and rank of an account for a specific leaderboard using GD-Sync cloud storage.
## If the user has no score submission on the leaderboard, Score will be 0 and Rank -1.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.LEADERBOARD_GET_SCORE_RESPONSE_CODE] response code.
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
## [br][b]page_size -[/b] The amount of scores returned. The maximum page size is 100.
## [codeblock]
## {
##    "Code" : 0,
##    "Result" :
##       {
##          "Score" : 100,
##          "Rank" : 1,
##          "Data" : {"CustomValue" : 1}
##       }
## }[/codeblock]
func leaderboard_get_score(leaderboard : String, username : String) -> Dictionary:
	if _connection_controller.is_local_check(): return {"Code" : 1}
	return await _data_controller.get_leaderboard_score(leaderboard, username)

## Submits a score to a leaderboard for the currently logged-in account using GD-Sync cloud storage.
## If the user already has a score submission, it will be overwritten.
## [br][br]Returns the result of the request as [constant ENUMS.LEADERBOARD_SUBMIT_SCORE_RESPONSE_CODE].
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
## [br][b]score -[/b] The score you want to submit.
## [br][b]data -[/b] Any extra information you would like to attach to the score. This dictionary can be a maximum of 2048 bytes in size.
func leaderboard_submit_score(leaderboard : String, score : int, data : Dictionary = {}) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.submit_score(leaderboard, score, data)

## Deletes a score from a leaderboard for the currently logged-in account using GD-Sync cloud storage.
## [br][br]Returns the result of the request as [constant ENUMS.LEADERBOARD_DELETE_SCORE_RESPONSE_CODE].
## [br]
## [br][b]leaderboard -[/b] The name of the leaderboard.
func leaderboard_delete_score(leaderboard : String) -> int:
	if _connection_controller.is_local_check(): return 1
	return await _data_controller.delete_score(leaderboard)









#endregion
# Steam Integration -----------------------------------------------------------
# *****************************************************************************
# -----------------------------------------------------------------------------
#region Steam Integration

## Returns true if the GodotSteam plugin is installed.
func steam_integration_enabled() -> bool:
	return _steam.steam_integration_enabled

## Links your GD-Sync account with your Steam account. Thiw will allow you to log into your GD-Sync account
## using your active Steam session.
## [br][br]Returns the result of the request as [constant ENUMS.LINK_STEAM_ACCOUNT_RESPONSE_CODE].
func steam_link_account() -> int:
	return await _steam.link_steam_account()

## Unlinks your GD-Sync account from Steam.
## [br][br]Returns the result of the request as [constant ENUMS.UNLINK_STEAM_ACCOUNT_RESPONSE_CODE].
func steam_unlink_account() -> int:
	return await _steam.unlink_steam_account()

## Logs into your GD-Sync account using the active Steam session.
## Only works if a Steam account has been linked.
## [br][br]Returns a [Dictionary] with the format seen below
## and the [constant ENUMS.STEAM_LOGIN_RESPONSE_CODE] response code.
## [br]
## [br]
## If the user is banned, it will include the "Banned" key, which contains the unix timestamp when the ban will
## expire. If the ban is permanent, the value will be -1.
## [br]
## [br][b]valid_time -[/b] The time in seconds how long the login session is valid.
## [codeblock]
## {
##    "Code" : 0,
##    "BanTime" : 1719973379
## }[/codeblock]
func steam_login(valid_time : float = 86400) -> Dictionary:
	return await _steam.steam_login(valid_time)

#endregion
