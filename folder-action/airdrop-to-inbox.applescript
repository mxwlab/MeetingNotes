use framework "Foundation"

property watcher_path : "__WATCHER__"
property audio_extensions : {"m4a", "mp3", "wav", "mp4", "aac", "flac"}

on run argv
	repeat with item_path in argv
		my ingest_airdrop_audio(contents of item_path, true)
	end repeat
end run

on «event facofget» this_folder given «class flst»:added_items
	repeat with added_item in added_items
		my ingest_airdrop_audio(POSIX path of (added_item as alias), false)
	end repeat
end «event facofget»

on run_task(executable_path, arguments_list, capture_output)
	set task to current application's NSTask's new()
	task's setExecutableURL:(current application's NSURL's fileURLWithPath:executable_path)
	task's setArguments:arguments_list
	if capture_output then
		set output_pipe to current application's NSPipe's pipe()
		task's setStandardOutput:output_pipe
	end if
	set launch_result to task's launchAndReturnError:(missing value)
	if not launch_result then error "无法运行 " & executable_path
	task's waitUntilExit()
	if (task's terminationStatus() as integer) is not 0 then error executable_path & " 执行失败"
	if capture_output then
		set output_data to output_pipe's fileHandleForReading()'s readDataToEndOfFile()
		set output_text to current application's NSString's alloc()'s initWithData:output_data encoding:(current application's NSUTF8StringEncoding)
		return output_text as text
	end if
	return ""
end run_task

on ingest_airdrop_audio(item_path, rethrow_errors)
	try
		set file_manager to current application's NSFileManager's defaultManager()
		if not (file_manager's fileExistsAtPath:item_path) then return
		set extension_name to ((current application's NSString's stringWithString:item_path)'s pathExtension()'s lowercaseString()) as text
		if extension_name is not in audio_extensions then return
		set quarantine_value to my run_task("/usr/bin/xattr", {"-p", "com.apple.quarantine", item_path}, true)
		set previous_delimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to ";"
		set quarantine_kind to text item 1 of quarantine_value
		set AppleScript's text item delimiters to previous_delimiters
		if quarantine_kind is "0059" or quarantine_kind is "59" then
			my run_task(watcher_path, {item_path}, false)
		end if
	on error error_message number error_number
		if rethrow_errors then error error_message number error_number
	end try
end ingest_airdrop_audio
