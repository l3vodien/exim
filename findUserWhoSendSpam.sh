#!/bin/bash

LOG="/var/log/exim_mainlog"
TODAY=$(date +"%b[ ]*%e")   # flexible date for single-digit days

# Sending limits
MAX_PER_HOUR=350
MAX_QUEUE=80
GMAIL_LIMIT=15
YAHOO_LIMIT=5
MS_LIMIT=5

echo ""
read -p "Enter the cPanel username: " CPUSER

if [ -z "$CPUSER" ]; then
    echo "No username entered. Exiting."
    exit 1
fi

# Detect home directory dynamically
HOMEDIR=$(getent passwd "$CPUSER" | cut -d: -f6)
if [ -z "$HOMEDIR" ]; then
    echo "Cannot determine home directory for $CPUSER."
    exit 1
fi

USER_MAIL_DIR="$HOMEDIR/mail"
if [ ! -d "$USER_MAIL_DIR" ]; then
    echo "No mail directory found for $CPUSER at $USER_MAIL_DIR"
    exit 0
fi

# Gather all email addresses for the user
EMAILS=$(find "$USER_MAIL_DIR" -mindepth 2 -maxdepth 2 -type d | awk -F/ '{print $(NF-1)"@"$NF}')
if [ -z "$EMAILS" ]; then
    echo "No email accounts found for $CPUSER in $USER_MAIL_DIR"
    exit 0
fi

# Temporary file for today's log lines
TODAY_LOG=$(mktemp)
grep -E "$TODAY" "$LOG" > "$TODAY_LOG"

# Collect all sender emails for this user
USER_LINES=""
for email in $EMAILS; do
    matches=$(grep -E "(F=<${email}>|<${email}>)" "$TODAY_LOG")
    [ -n "$matches" ] && USER_LINES="$USER_LINES"$'\n'"$matches"
done

if [ -z "$USER_LINES" ]; then
    echo "No outbound activity found for $CPUSER today."
    rm -f "$TODAY_LOG"
    exit 0
fi

# Extract recipient domains
RECIPIENT_DOMAINS=$(echo "$USER_LINES" \
    | grep -oP "(?<= to=<)[^>]+|(?<=@)[A-Za-z0-9.-]+\.[A-Za-z]{2,}" \
    | sed 's/>//' \
    | awk -F@ '{print $2}' \
    | sort -u)

echo ""
echo "FOUND DOMAINS SENT TO BY $CPUSER:"

for dom in $RECIPIENT_DOMAINS; do
    count=$(echo "$USER_LINES" | grep -i "$dom" | wc -l)
    flag=""

    [ "$count" -gt "$MAX_PER_HOUR" ] && flag+=" [EXCEEDS HOURLY MAX $MAX_PER_HOUR]"
    [ "$count" -gt "$MAX_QUEUE" ] && flag+=" [EXCEEDS QUEUE LIMIT $MAX_QUEUE]"
    [[ "$dom" =~ gmail\.com$ ]] && [ "$count" -gt "$GMAIL_LIMIT" ] && flag+=" [EXCEEDS GMAIL RATE $GMAIL_LIMIT/80s]"
    [[ "$dom" =~ yahoo\.com$ ]] && [ "$count" -gt "$YAHOO_LIMIT" ] && flag+=" [EXCEEDS YAHOO RATE $YAHOO_LIMIT/80s]"
    [[ "$dom" =~ (hotmail\.com|live\.com|outlook\.com|microsoft\.com)$ ]] && [ "$count" -gt "$MS_LIMIT" ] && flag+=" [EXCEEDS MS RATE $MS_LIMIT/80s]"

    echo "DOMAIN: $dom -> MAX DEFER: $count$flag"
done

rm -f "$TODAY_LOG"
echo ""
