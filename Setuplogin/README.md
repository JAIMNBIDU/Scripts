# setup-logging

On-demand terminal session logging with a visible REC marker. Type `logme` to start capturing a session, `exit` to stop. Nothing records until you ask it to.

## Setup

```bash
bash setup-logging.sh
```

Runs once. Adds a `logme` function to your `~/.zshrc` and creates `~/terminal-logs/`. Open a new terminal afterward.

> **zsh only.** The function and the red prompt marker use zsh syntax. Not for bash.

## Usage

```bash
logme     # start recording -> writes ~/terminal-logs/<timestamp>.log
exit      # stop
```

While recording, your prompt shows a red `[REC HH:MM:SS]` tag so you never forget a session is being captured. Each run writes its own timestamped log via `script`.

Re-running `setup-logging.sh` is safe. It strips its old block before re-adding, so you won't get duplicates.

## License

MIT.
