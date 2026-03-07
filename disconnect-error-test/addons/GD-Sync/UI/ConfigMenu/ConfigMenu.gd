@tool
extends Control

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

var plugin

var menu_open : bool = false

var updater : Updater

func _ready():
	if plugin == null: return
	if ProjectSettings.has_setting("GD-Sync/publicKey"):
		%PublicKey.text = ProjectSettings.get_setting("GD-Sync/publicKey")
	if ProjectSettings.has_setting("GD-Sync/privateKey"):
		%PrivateKey.text = ProjectSettings.get_setting("GD-Sync/privateKey")
	if ProjectSettings.has_setting("GD-Sync/protectedMode"):
		%Protected.button_pressed = ProjectSettings.get_setting("GD-Sync/protectedMode")
	if ProjectSettings.has_setting("GD-Sync/csharp"):
		%CSharpSupport.button_pressed = ProjectSettings.get_setting("GD-Sync/csharp")
	if ProjectSettings.has_setting("GD-Sync/useSenderID"):
		%SenderID.button_pressed = ProjectSettings.get_setting("GD-Sync/useSenderID")
	if ProjectSettings.has_setting("GD-Sync/uniqueUsername"):
		%UniqueUsernames.button_pressed = ProjectSettings.get_setting("GD-Sync/uniqueUsername")
	if ProjectSettings.has_setting("GD-Sync/scriptValidation"):
		%ScriptValidation.button_pressed = ProjectSettings.get_setting("GD-Sync/scriptValidation")
	
	updater = Updater.new()
	add_child(updater)

func update_ready() -> void:
	%DefaultPannel.visible = false
	%UpdatePanel.visible = true

func _input(event):
	if !menu_open: return
	if event is InputEventKey:
		if event.is_pressed() and event.keycode == KEY_ESCAPE:
			close()

func open():
	menu_open = true
	$AnimationPlayer.play("Open")
	
	var scale : float = size.y/1080.0
	$CenterContainer/LogoAnchor/Logo.scale = Vector2.ONE*scale
	$CenterContainer/UIAnchor/UI.scale = Vector2.ONE*scale

func close():
	menu_open = false
	$AnimationPlayer.play_backwards("Open")

func _on_PublicKey_text_changed(new_text):
	ProjectSettings.set_setting("GD-Sync/publicKey", new_text)
	ProjectSettings.save()

func _on_PrivateKey_text_changed(new_text):
	ProjectSettings.set_setting("GD-Sync/privateKey", new_text)
	ProjectSettings.save()

func _on_c_sharp_support_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/csharp", button_pressed)
	ProjectSettings.save()
	
	if button_pressed:
		plugin.enable_csharp_api()
	else:
		plugin.disable_csharp_api()

func _on_protected_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/protectedMode", button_pressed)
	ProjectSettings.save()

func _on_unique_usernames_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/uniqueUsername", button_pressed)
	ProjectSettings.save()

func _on_sender_id_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/useSenderID", button_pressed)
	ProjectSettings.save()

func _on_script_validation_toggled(button_pressed) -> void:
	ProjectSettings.set_setting("GD-Sync/scriptValidation", button_pressed)
	ProjectSettings.save()

func _on_description_meta_clicked(meta):
	if meta == "log":
		meta = OS.get_user_data_dir()+"/GD-Sync/logs"
	OS.shell_open(meta)

func _on_update_button_pressed() -> void:
	%LoadIcon.play()
	$AnimationPlayer.play("Downloading")
	
	var result : bool = await updater.update_repo()
	
	%DefaultPannel.visible = true
	%UpdatePanel.visible = false
	$AnimationPlayer.play_backwards("Downloading")
	
	if result:
		plugin.show_message("[color=#61ff71][b]The newest version of GD-Sync has been installed. Please restart the engine to complete the update.[/b][/color]", 10.0)
	else:
		plugin.show_message("[color=indianred][b]GD-Sync failed to update. Please try downloading it from the Godot Asset Library instead.[/b][/color]")
