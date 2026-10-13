-- name: Reminders
-- icon: checklist
-- group: Add to
-- description: Adds the text as a reminder

-- Adds the selection as a reminder in the default list; macOS asks once whether Popoli may use Reminders.
on run argv
	set theText to item 1 of argv
	set theTitle to paragraph 1 of theText
	tell application "Reminders"
		if (count of paragraphs of theText) > 1 then
			make new reminder with properties {name:theTitle, body:theText}
		else
			make new reminder with properties {name:theTitle}
		end if
	end tell
	return "Added to Reminders"
end run
