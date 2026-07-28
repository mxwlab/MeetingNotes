on run argv
	try
		if (count of argv) > 0 then
			display dialog (item 1 of argv) with title "MeetingNotes" ¬
				buttons {"重新输入"} default button "重新输入" with icon caution
		end if
		display dialog "请输入你的 DeepSeek API Key" default answer "" ¬
			with title "MeetingNotes 首次设置" ¬
			with icon note ¬
			buttons {"取消", "继续"} default button "继续" cancel button "取消" ¬
			giving up after 600 ¬
			with hidden answer
		set entered_key to text returned of result
		if entered_key is "" then error number -128
		return entered_key
	on error number -128
		error number -128
	end try
end run
