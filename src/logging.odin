package main

import "core:fmt"
import "core:encoding/ansi"

WARNING_YELLOW_TEXT :: ansi.CSI + ansi.FG_YELLOW + ansi.SGR + "WARNING: " + ansi.CSI + ansi.RESET + ansi.SGR
ERROR_RED_TEXT :: ansi.CSI + ansi.FG_RED + ansi.SGR + "ERROR: " + ansi.CSI + ansi.RESET + ansi.SGR
NOTE_BLUE_TEXT ::ansi.CSI + ansi.FG_BLUE + ansi.SGR + "NOTE: " + ansi.CSI + ansi.RESET + ansi.SGR

log_error :: proc(format: string, args: ..any) -> int
{
	n := fmt.print(ERROR_RED_TEXT)
	return n + fmt.printfln(format, ..args)
}

log_warning :: proc(format: string, args: ..any) -> int
{
	n := fmt.print(WARNING_YELLOW_TEXT)
	return n + fmt.printfln(format, ..args)
}

log_note :: proc(format: string, args: ..any) -> int
{
	n := fmt.print(NOTE_BLUE_TEXT)
	return n + fmt.printfln(format, ..args)
}
