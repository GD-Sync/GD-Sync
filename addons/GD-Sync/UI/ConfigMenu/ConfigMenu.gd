@tool
extends Control

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

var menu_open : bool = false

func _ready():
	if ProjectSettings.has_setting("GD-Sync/publicKey"):
		%PublicKey.text = ProjectSettings.get_setting("GD-Sync/publicKey")
	if ProjectSettings.has_setting("GD-Sync/privateKey"):
		%PrivateKey.text = ProjectSettings.get_setting("GD-Sync/privateKey")
	if ProjectSettings.has_setting("GD-Sync/protectedMode"):
		%Protected.button_pressed = ProjectSettings.get_setting("GD-Sync/protectedMode")
	if ProjectSettings.has_setting("GD-Sync/uniqueUsername"):
		%UniqueUsernames.button_pressed = ProjectSettings.get_setting("GD-Sync/uniqueUsername")

func _input(event):
	if !menu_open: return
	if event is InputEventKey:
		if event.is_pressed() and event.keycode == KEY_ESCAPE:
			close()

func open():
	menu_open = true
	$AnimationPlayer.play("Open")
	
	var scale : float = get_viewport_rect().size.y/1080.0
	$CenterContainer/LogoControl.scale = Vector2.ONE*scale
	$CenterContainer/UI.scale = Vector2.ONE*scale

func close():
	menu_open = false
	$AnimationPlayer.play_backwards("Open")

func _on_PublicKey_text_changed(new_text):
	ProjectSettings.set_setting("GD-Sync/publicKey", new_text)
	ProjectSettings.save()

func _on_PrivateKey_text_changed(new_text):
	ProjectSettings.set_setting("GD-Sync/privateKey", new_text)
	ProjectSettings.save()

func _on_protected_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/protectedMode", button_pressed)
	ProjectSettings.save()

func _on_unique_usernames_toggled(button_pressed):
	ProjectSettings.set_setting("GD-Sync/uniqueUsername", button_pressed)
	ProjectSettings.save()

func _on_description_meta_clicked(meta):
	OS.shell_open(meta)
