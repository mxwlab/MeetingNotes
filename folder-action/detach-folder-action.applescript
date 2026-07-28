on run argv
	set downloads_path to item 1 of argv
	set script_path to item 2 of argv
	tell application "System Events"
		-- 按数字索引反向遍历并逐项 try 包裹：System Events 在存在多个 folder
		-- action 时，用 `repeat with x in folder actions` 的隐式枚举容易抛
		-- -1728；反向定长索引 + try 可容忍单项失效并安全删除目标关联。
		set action_count to (count of folder actions)
		repeat with i from action_count to 1 by -1
			try
				set candidate_action to folder action i
				if path of candidate_action is downloads_path then
					set script_count to (count of scripts of candidate_action)
					repeat with j from script_count to 1 by -1
						try
							set candidate_script to script j of candidate_action
							if POSIX path of candidate_script is script_path then
								delete candidate_script
							end if
						end try
					end repeat
					try
						if (count of scripts of candidate_action) is 0 then
							delete candidate_action
						end if
					end try
				end if
			end try
		end repeat
	end tell
end run
