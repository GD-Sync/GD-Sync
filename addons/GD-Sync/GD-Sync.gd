@tool
extends EditorPlugin

#Copyright (c) 2023 Thomas Uijlen, GD-Sync.
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

func _enable_plugin():
	add_autoload_singleton("GDSync", "res://addons/GD-Sync/MultiplayerClient.gd")
	
	print("GD-Sync addon enabled!")
	print("Please enter your public and private key under Project->Tools->GD-Sync")

func _disable_plugin():
	remove_tool_menu_item("GD-Sync")
	remove_custom_type("PropertySynchronizer")
	remove_custom_type("NodeInstantiator")
	remove_autoload_singleton("GDSync")

var config_menu : Control
func _enter_tree():
	config_menu = load("res://addons/GD-Sync/UI/ConfigMenu/ConfigMenu.tscn").instantiate()
	get_editor_interface().get_base_control().add_child(config_menu)
	add_tool_menu_item("GD-Sync", config_selected)
	
	add_custom_type("PropertySynchronizer",
			"Node",
			load("res://addons/GD-Sync/Scripts/Types/PropertySynchronizer.gd"),
			load("res://addons/GD-Sync/UI/Icons/SynchronizeIcon.png"))
	add_custom_type("NodeInstantiator",
			"Node",
			load("res://addons/GD-Sync/Scripts/Types/NodeInstantiator.gd"),
			load("res://addons/GD-Sync/UI/Icons/NodeInstantiator.png"))

func _exit_tree():
	config_menu.free()

func config_selected():
	config_menu.open()
