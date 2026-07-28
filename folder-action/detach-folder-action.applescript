on run argv
	set downloads_path to item 1 of argv
	set script_path to item 2 of argv
	tell application "System Events"
		repeat with candidate_action in folder actions
			if path of candidate_action is downloads_path then
				set target_action to candidate_action
				repeat with candidate_script in scripts of target_action
					if POSIX path of candidate_script is script_path then
						delete candidate_script
						exit repeat
					end if
				end repeat
				if (count scripts of target_action) is 0 then delete target_action
				exit repeat
			end if
		end repeat
	end tell
end run
