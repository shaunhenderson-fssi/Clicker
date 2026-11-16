This program can interact with other Windows programs (using the Win32 API).

It has the following features:
- Can click on named buttons
- Can type text into fields
- Rudimentary scripting
- Can load/save to script files
- Can record buttons, mouse clicks, wheel scrolling, typed text, and keyboard shortcuts as scripts
- Can toggle the live hover text inspector on or off, this is useful when creating scripts to inspect the Windows API
- Can automatically run a script via command line arguments, this is useful for running multiple scripts via batch file
- Can run scripts in console mode and print script output to standard output
- Can run the selected script lines from the editor
- Can step through individual script commands, this is useful for debugging scripts
- Comments

Run a script without opening the editor:

```text
Clicker.exe --console path\to\script.script
```

Console mode returns exit code `0` on success and `1` if the script or program encounters an error. The existing `Clicker.exe <script-file>` invocation
continues to run the script in the GUI.

It can perform the following tasks:
- ClickButton <buttonText>
- ClickElement
- MouseClick <x> <y> [Left|Right|Middle]
- MouseWheel <x> <y> <delta>
- SetText <dialogName> <controlName> <value>
- PressKey <keyName> (you can also specify combinations like "Alt+F4" or "Control+Enter")
- TypeText <text>
- TypePassword <encryptedText> or TypePassword <form|dialog> <field|control> <encryptedText> (this means unencrypted passwords are not stored in scripts)
- Load <filename> (searched relative to the current script, Clicker.exe, then C:\Scripts; `.script` extension is optional)
- SetPause <time> (global pause time in between commands)
- Sleep <milliseconds>
- Alias <name> <value>
- Assert <Button|Edit|Memo> <name|id|hwnd> "Expected text"
- Assert <Button|Edit|Memo> <WindowName> <name|id|hwnd> "Expected text"
- Assert <Button|Edit|Memo> <screenX> <screenY> "Expected text"
- Assert <Button|Edit|Memo> <coordinateAlias> "Expected text"
- Close <windowName>
- Stop (halts the current script immediately and skips remaining commands)
- Assert Color <x> <y> <#RRGGBB|colorName> (useful for detecting Club+ logo)
- LaneTool
- DumpWindow <windowName>
- DumpHere

`Assert Color` checks a screen pixel, for example `Assert Color 121 254 #1a2b3c` or `Assert Color 321 222 red`. The custom named color `clYellowPNS` is also
available and is equivalent to `#FED803` (RGB 254,216,3). A color mismatch stops the script with an error. It samples up to 10 times at 100 ms intervals
and passes when at least 8 samples match the expected color. This is because sometimes there are animations on the screen.

`Assert Memo` checks the full text in a memo control, treating line breaks as spaces. For example, a memo containing three lines can be checked with:

```text
Assert Memo ID:1449582 "Barcode check digit is invalid Barcode 9412345678901 Please try again"
```

Memo IDs are searched under the configured window first, then across other top-level windows (useful for popup dialogs). If more than one memo has that
ID, target it by HWND instead:

```text
Assert Memo HWND:001616E6 "Expected text"
```

To avoid changing IDs and HWNDs, use screen coordinates inside the memo. You can use the inspector tool to get the position of elements on the screen.
The coordinates are relative to the desktop (top left is 0,0), the same as `MouseClick`:

```text
Assert Memo 506 366 "Product not found"
```

Screen coordinates can also be stored as an alias:

```text
Alias dialog 506 366
Assert Memo dialog "Product not found"
```

Coordinate aliases can assert buttons, edits, and memos:

```text
Alias search_button 412 439
Assert Button search_button "Search"
ClickButton search_button

Assert Edit 512 539 "Expected value"
Alias dialog 612 639
Assert Memo dialog "Expected memo text"
ClickButton dialog OK
```

The control under those coordinates (including a memo nested under another child control) is checked.

In the program, use Help > Reference to get a list of commands and an explanation of usage

The main window follows the Windows app theme setting (Settings > Personalization > Colors > Choose your mode). If you use Custom mode, set the default app
mode to Dark. Clicker updates automatically when the Windows setting changes.

Script lines support inline comments beginning with `;`, `#`, or `//`. The comment marker and everything after it are ignored through the end of the line.
Comment markers inside double-quoted text are preserved. A `#RRGGBB` value used by `Assert Color` is treated as a color, not a comment; other `#` markers
start comments.

Use the Record button to start capturing input and Stop to finish. The recorded commands appear in the script editor; use File > Save to save them as a
`.script` file. Select one or more lines in the editor and click **Run selected** to execute only those lines.
