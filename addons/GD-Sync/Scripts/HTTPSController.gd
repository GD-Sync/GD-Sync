extends Node

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
