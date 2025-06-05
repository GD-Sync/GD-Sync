extends Control

#A simple text chat system with support for multiple channels.
#Users can join and leave channels and can only send and receive messages from channels they are in.

#This chat system saves bandwith by actively making use of player data.
#In this case, player data is used to check if a client is listening to a channel before actually the message.

signal typing_started
signal typing_stopped

##The action name to open the chat
@export var open_action_name : String
##The action name to close the chat
@export var cancel_action_name : String
##The default channel which is joined automatically
@export var default_channel : int = 0
##The maximum amount of messages that can be displayed in the chat box
@export var message_display_count : int = 10
##The maximum length in characters of a message
@export var max_message_length : int = 100
##Makes the chat to automatically display usernames. Use GDSync.set_username() to set usernames.
@export var show_usernames : bool = true
##Automatically assigns colors to the usernames in chat. Use GDSync.set_player_data("Color", color) to set colors.
@export var show_client_colors : bool = true
##Adds a number in front of messages, showing which channel it came from.
@export var show_channel_id : bool = false
##Keeps the message history when switching between scenes.
@export var keep_messages_between_scenes : bool = true

static var saved_messages : Array = []
static var last_lobby : String = ""

var _current_typing_channel : int
var _listening_channels : Array = []
var _typing : bool = false

var _template_message : Node

func _ready():
	_template_message = %TemplateMessage
	_template_message.get_parent().remove_child(_template_message)
	
	_current_typing_channel = default_channel
	enter_channel(_current_typing_channel)
	
#	Restore channels
	for channel in GDSync.get_player_data(GDSync.get_client_id(), "TextChannels", []):
		enter_channel(channel)
	
#	Clear messages if lobby changed
	if last_lobby != GDSync.get_lobby_name():
		last_lobby = GDSync.get_lobby_name()
		saved_messages.clear()
	
#	Restore existing messages
	for message_data in saved_messages:
		_receive_message(message_data[0],message_data[1],message_data[2], true)
	
	GDSync.expose_func(_receive_message)

func start_typing():
	if _typing: return
	_typing = true
	%TypingContainer.visible = _typing
	%TextEdit.grab_focus()
	typing_started.emit()

func stop_typing():
	if !_typing: return
	_typing = false
	%TypingContainer.visible = _typing
	%TextEdit.text = ""
	typing_stopped.emit()

func set_current_typing_channel(channel : int):
#	Users cant type in channels they arent in
	if !_listening_channels.has(channel): return
	
	_current_typing_channel = channel

func enter_channel(channel : int):
	if _listening_channels.has(channel): return
	_listening_channels.append(channel)
	
#	Update listening channels on other clients
	GDSync.set_player_data("TextChannels", _listening_channels)

func leave_channel(channel : int):
	if !_listening_channels.has(channel): return
	_listening_channels.erase(channel)
	
#	Update listening channels on other clients
	GDSync.set_player_data("TextChannels", _listening_channels)

func _on_text_changed():
	var text_edit : TextEdit = %TextEdit
	var current_column : int = text_edit.get_caret_column()
	var current_line : int = text_edit.get_caret_line()
	
#	Limit text message size
	if text_edit.text.length() > max_message_length:
		text_edit.text = text_edit.text.left(max_message_length)
	
	text_edit.set_caret_column(current_column)
	text_edit.set_caret_line(current_line)

func _send_message():
	var text = %TextEdit.text
	if text.length() == 0: return
	
#	Add the message to your own chat
	_receive_message(text, _current_typing_channel, GDSync.get_client_id())
	
	for client_id in GDSync.get_all_clients():
#		Filter out yourself
		if client_id == GDSync.get_client_id(): continue
		
#		Check if the user is listening to this channel
		if !GDSync.get_player_data(client_id, "TextChannels", []).has(_current_typing_channel): continue
		
#		Send the message to the specific client
		GDSync.call_func_on(client_id, _receive_message, [text, _current_typing_channel, GDSync.get_client_id()])
	
	stop_typing()

func _receive_message(text : String, channel : int, from : int, from_save : bool = false):
#	Check if this client is actually listening to the received channel
	if !_listening_channels.has(channel): return
	
#	Save messages if enabled
	if keep_messages_between_scenes and !from_save:
		saved_messages.append([text, channel, from])
		if saved_messages.size() > message_display_count:
			saved_messages.pop_front()
	
	#	Show the message in chat
	var message : String = ""
	
	if show_channel_id: message += "["+str(channel)+"]"
	if show_usernames:
		if show_client_colors:
			message += "[[color="+GDSync.get_player_data(from, "Color", Color.WHITE).to_html(false)+"]"+GDSync.get_player_data(from, "Username", "Unkown")+"[/color]]"
		else:
			message += "["+GDSync.get_player_data(from, "Username", "Unkown")+"]"
	if show_channel_id || show_usernames: message += " "
	message += text
	
	var message_node : Node = _template_message.duplicate()
	message_node.text = message
	%MessageContainer.add_child(message_node)
	
#	Pop oldest message if the maximum has been reached
	if %MessageContainer.get_child_count() > message_display_count:
		%MessageContainer.get_child(0).queue_free()
	
#	Make sure the chat follows the recent messages
#	We have to wait for two frames, otherwise ensure_control_visible wont function properly
	await get_tree().process_frame
	%ScrollContainer.ensure_control_visible.call_deferred(message_node)

func _input(event):
	if event.is_action_pressed(open_action_name):
		if _typing:
			_send_message()
		else:
			get_viewport().set_input_as_handled()
			start_typing()
	
	if event.is_action_pressed(cancel_action_name):
		if _typing: get_viewport().set_input_as_handled()
		stop_typing()
