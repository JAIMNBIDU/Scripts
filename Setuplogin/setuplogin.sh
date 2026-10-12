#!/usr/bin/env bash
# setup-logging.sh
# Run once:  bash setup-logging.sh
# Manual on-demand logging with a visible REC marker.
# Type `logme` to start recording. Prompt shows red [REC HH:MM:SS] while active.
# Type `exit` to stop. A new terminal does nothing until you type `logme` again.

RC="$HOME/.zshrc"
[ -f "$RC" ] || touch "$RC"

mkdir -p ~/terminal-logs

sed -i '/# >>> auto-terminal-logging >>>/,/# <<< auto-terminal-logging <<</d' "$RC"
sed -i '/# >>> manual-logme >>>/,/# <<< manual-logme <<</d' "$RC"

cat >> "$RC" << 'EOF'

logme() {
  mkdir -p ~/terminal-logs
  echo "Recording to ~/terminal-logs/  (type exit to stop)"
  LOGME_ACTIVE=1 script -f -q ~/terminal-logs/$(date +%F_%H-%M-%S).log
}
if [[ -n "$LOGME_ACTIVE" ]]; then
  PROMPT='%F{red}[REC %D{%H:%M:%S}]%f '$PROMPT
fi
EOF

echo "Done. Open a NEW terminal, then type:  logme"
echo "While recording your prompt shows a red [REC HH:MM:SS] marker."
echo "Stop recording:  exit"

