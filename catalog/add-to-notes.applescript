-- name: Notes
-- icon: note.text
-- group: Add to
-- description: Adds the text as a new note in Notes

-- Adds the selection as a new note in the default account; macOS asks once whether Popoli may use Notes.
on run argv
	set theText to item 1 of argv
	set theBody to ""
	repeat with theLine in paragraphs of theText
		set theBody to theBody & "<div>" & my escape(theLine as text) & "</div>"
	end repeat
	tell application "Notes" to make new note with properties {body:theBody}
	return "Added to Notes"
end run

on escape(theText)
	set AppleScript's text item delimiters to "&"
	set theParts to text items of theText
	set AppleScript's text item delimiters to "&amp;"
	set theText to theParts as text
	set AppleScript's text item delimiters to "<"
	set theParts to text items of theText
	set AppleScript's text item delimiters to "&lt;"
	set theText to theParts as text
	set AppleScript's text item delimiters to ""
	return theText
end escape
