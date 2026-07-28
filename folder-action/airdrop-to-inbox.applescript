property watcher_path : "__WATCHER__"
property audio_extensions : {"m4a", "mp3", "wav", "mp4", "aac", "flac"}

-- Manual entry point used by the installer smoke test. Folder Actions invoke
-- the event handler below instead.
on run argv
	repeat with item_path in argv
		my ingest_airdrop_audio(POSIX file (contents of item_path), true)
	end repeat
end run

-- Raw event form of “adding folder items to … after receiving …”.
-- This compiles reliably with osacompile even when Folder Action terminology
-- is not loaded into the command-line AppleScript context.
on «event facofget» this_folder given «class flst»:added_items
	repeat with added_item in added_items
		my ingest_airdrop_audio(added_item, false)
	end repeat
end «event facofget»

on ingest_airdrop_audio(incoming_item, rethrow_errors)
	try
		set item_path to POSIX path of (incoming_item as alias)
		do shell script "/bin/test -f " & quoted form of item_path
		set extension_name to do shell script "/usr/bin/basename " & quoted form of item_path & " | /usr/bin/awk -F. '{print tolower($NF)}'"
		if extension_name is not in audio_extensions then return
		
		set quarantine_value to do shell script "/usr/bin/xattr -p com.apple.quarantine " & quoted form of item_path
		set previous_delimiters to AppleScript's text item delimiters
		set AppleScript's text item delimiters to ";"
		set quarantine_kind to text item 1 of quarantine_value
		set AppleScript's text item delimiters to previous_delimiters
		
		if quarantine_kind is "0059" or quarantine_kind is "59" then
			do shell script quoted form of watcher_path & " " & quoted form of item_path
		end if
	on error error_message number error_number
		-- Missing quarantine metadata, incomplete transfers, and vanished files
		-- are intentionally ignored. A later Folder Action event can retry.
		if rethrow_errors then error error_message number error_number
	end try
end ingest_airdrop_audio
