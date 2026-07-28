on run argv
	set downloads_path to item 1 of argv
	set script_path to item 2 of argv
	tell application "System Events"
		set folder actions enabled to true
		set target_action to missing value
		repeat with candidate_action in folder actions
			if path of candidate_action is downloads_path then
				set target_action to candidate_action
				exit repeat
			end if
		end repeat
		if target_action is missing value then
			set target_action to make new folder action at end of folder actions with properties {path:downloads_path}
		end if
		
		set already_attached to false
		repeat with candidate_script in scripts of target_action
			if POSIX path of candidate_script is script_path then
				set already_attached to true
				exit repeat
			end if
		end repeat
		if not already_attached then
			tell target_action to make new script at end of scripts with properties {POSIX path:script_path}
		end if
	end tell
end run
