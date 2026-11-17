# machine-load.md

Before a task that can demand much CPU or GPU, the session reads the temperature.

- Heavy: a task that can demand much processing or GPU, typically graphics and 3D rendering (game engine run or export, a browser with WebGL, a local AI model). Day-to-day test suites, builds, containers and `scripts/validate.sh` are not heavy: they run directly, with no reading.
- Run a heavy task as `bash scripts/heavy-run.sh -- <command>`, in the background: the wait can reach 30 minutes. It reads the hotter of CPU and GPU; under 88 °C it runs at once; at 88 °C or more it waits until 85 °C or less.
- Exit 75: still above 85 °C after 30 minutes, nothing ran. Tell the human, with the last reading the script printed. Never run the task outside the script to skip the wait, unless the human orders it.
- A heavy task that is not one command (e.g. driving a 3D page in the browser): read `bash scripts/heavy-run.sh --status` first and follow the same limits.
- Nothing queues: no run waits for another session.
- Never stop another session's processes or containers: tell the human what is consuming the machine.
