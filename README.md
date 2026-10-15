This program can interact with other Windows programs (using the Win32 API).

It has the following features:
- Can click on named buttons
- Can type text into fields
- Rudimentary scripting
- Can load/save to script files
- Can record buttons, mouse clicks, wheel scrolling, typed text, and keyboard shortcuts as scripts
- Can toggle the live hover text inspector on or off
- Can automatically run a script via command line arguments
- Can run scripts in console mode and print script output to standard output
- Comments

Run a script without opening the editor:

```text
Clicker.exe --console path\to\script.script
```

Console mode returns exit code `0` on success and `1` if the script or program
encounters an error. The existing `Clicker.exe <script-file>` invocation
continues to run the script in the GUI.

It can perform the following tasks:
- ClickButton
- ClickElement
- MouseClick <x> <y> [Left|Right|Middle]
- MouseWheel <x> <y> <delta>
- SetText <dialogName> <controlName> <value>
- PressKey <keyName>
- TypeText <text>
- TypePassword <encryptedText> or TypePassword <form|dialog> <field|control> <encryptedText>
- Load <filename> (searched relative to the current script, Clicker.exe, then C:\Scripts; `.script` extension is optional)
- SetPause <time>
- Sleep <milliseconds>
- Alias <name> <value>
- If <"Button"|"Edit"> <WindowName> <name|id|hwnd> "Expected text"
- Close <windowName>
- Stop (halts the current script immediately and skips remaining commands)
- Assert Color <x> <y> <#RRGGBB|colorName>
- LaneTool
- DumpWindow <windowName>
- DumpHere

`Assert Color` checks a screen pixel, for example `Assert Color 121 254 #1a2b3c`
or `Assert Color 321 222 red`. The custom named color `clYellowPNS` is also
available and is equivalent to `#FED803` (RGB 254,216,3). A color mismatch
stops the script with an error. It samples up to 10 times at 100 ms intervals
and passes when at least 8 samples match the expected color.

In the program, use Help > Reference to get a list of commands and an explanation of usage

Script lines support inline comments beginning with `;`, `#`, or `//`. The
comment marker and everything after it are ignored through the end of the line.
Comment markers inside double-quoted text are preserved. A `#RRGGBB` value
used by `Assert Color` is treated as a color, not a comment; other `#` markers
start comments.

Use the Record button to start capturing input and Stop to finish. The recorded
commands appear in the script editor; use File > Save to save them as a `.script`
file.
