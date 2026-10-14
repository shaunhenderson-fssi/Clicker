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
- LaneTool
- DumpWindow <windowName>
- DumpHere

In the program, use Help > Reference to get a list of commands and an explanation of usage

Use the Record button to start capturing input and Stop to finish. The recorded
commands appear in the script editor; use File > Save to save them as a `.script`
file.
