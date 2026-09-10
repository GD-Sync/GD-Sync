extends Node

#Copyright (c) 2023-present GD-Sync.
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
var logger

var active_lb : String = ""

func _ready():
	GDSync = get_node("/root/GDSync")
	name = "HTTPSController"
	connection_controller = GDSync._connection_controller
	data_controller = GDSync._data_controller
	logger = GDSync._logger

func perform_https_request(endpoint : String, message : Dictionary) -> Dictionary:
	logger.write_log("Making HTTP request. <"+endpoint+"><"+str(message)+">", "[HTTP]")
	
	if !GDSync.is_active():
		logger.write_error("Failed HTTP request as the plugin is not active. <"+endpoint+">", "[HTTP]")
		push_error("You must first start the plugin using GDSync.start_multiplayer() before using any cloudstorage functions.")
		return {"Code" : 1}
	
	if active_lb.is_empty():
		logger.write_error("Failed HTTP request, no load balancer resolved. <"+endpoint+">", "[HTTP]")
		return {"Code" : 1}
	
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = 20
	add_child(request)
	
	message["PublicKey"] = connection_controller._PUBLIC_KEY
	
	request.request(
		active_lb+"/"+endpoint,
		["Content-Type: text/plain"],
		HTTPClient.METHOD_POST,
		var_to_str(message)
	)
	
	var result = await request.request_completed
	
	logger.write_log("Completed HTTP request. <"+endpoint+"><"+str(result[1])+">", "[HTTP]")
	
	if result[1] == 200:
		var text : String = result[3].get_string_from_ascii()
		var received_message : Dictionary = str_to_var(text)
		logger.write_log("Successful HTTP request. <"+endpoint+"><"+text+">", "[HTTP]")
		return received_message
	else:
		logger.write_error("Failed HTTP request. <"+endpoint+"><"+str(result[1])+">", "[HTTP]")
		return {"Code" : 1 if result[1] != 503 else 3}

func ping_https(url : String, timeout_seconds : float = 3.0) -> float:
	logger.write_log("HTTPS ping. <"+url+">", "[HTTP]")
	var request : HTTPRequest = HTTPRequest.new()
	request.timeout = timeout_seconds
	add_child(request)
	
	var started_ms : int = Time.get_ticks_msec()
	var error : Error = request.request(url, [], HTTPClient.METHOD_GET)
	if error != OK:
		request.queue_free()
		logger.write_error("HTTPS ping failed to start. <"+url+"><"+str(error)+">", "[HTTP]")
		return -1.0
	
	var result = await request.request_completed
	var elapsed_ms : float = float(Time.get_ticks_msec() - started_ms)
	request.queue_free()
	
	var response_code : int = result[1]
	if response_code <= 0:
		logger.write_error("HTTPS ping failed. <"+url+"><"+str(response_code)+">", "[HTTP]")
		return -1.0
	
	logger.write_log("HTTPS ping complete. <"+url+"><"+str(elapsed_ms)+"ms><"+str(response_code)+">", "[HTTP]")
	return elapsed_ms
