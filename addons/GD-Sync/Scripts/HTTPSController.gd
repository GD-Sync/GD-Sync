extends Node

var GDSync
var connection_controller
var data_controller

var active_lb : String = ""

func _ready():
	GDSync = get_node("/root/GDSync")
	connection_controller = GDSync._connection_controller
	data_controller = GDSync._data_controller

func perform_https_request(endpoint : String, message : Dictionary) -> Dictionary:
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 20
	add_child(request)
	
	message["PublicKey"] = connection_controller._PUBLIC_KEY
	
	request.request(
		active_lb+"/"+endpoint,
		[],
		HTTPClient.METHOD_GET,
		var_to_str(message)
	)
	
	var result = await request.request_completed
	
	if result[1] == 200:
		var text : String = result[3].get_string_from_ascii()
		var received_message : Dictionary = str_to_var(text)
		return received_message
	else:
		return {"Code" : 1 if result[1] != 503 else 3}
