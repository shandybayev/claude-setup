# Close only the browser process you launched, never by image name

**Rule:** Every probe or builder task that launches its own browser instance must record the process id of the browser it launched (or use its own unique profile/user-data directory), and at the end close only that process tree, or only processes whose command line contains that unique profile path. Never close a browser by image name (for example `taskkill /IM chrome.exe`, `pkill chrome`, or `Stop-Process -Name chrome`).

**Why:** A kill-by-name command closes every running instance of that browser on the machine, including the human's own browser windows, not just the one the agent launched. On a real project this closed every one of a human's own browser windows at once.

**How to apply:** State this explicitly in every probe and builder prompt that launches a browser: record the PID you launch, and at the end kill only that PID tree, or only processes matching your own unique `--user-data-dir`. After a probe finishes, check that the human's own browser process count is unchanged. See [[browser-testing-via-subagents]].
