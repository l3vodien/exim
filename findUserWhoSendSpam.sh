#!/bin/bash

LOG="/var/log/exim_mainlog"
TODAY=$(date +"%b %d")

# Sending limits
MAX_PER_HOUR=350
MAX_QUEUE=80
GMAIL_LIMIT=15
YAHOO_LIMIT=5
MS_LIMIT=5
MAX_SPAM_8H=20
MAX_BULK_8H=30
MAX_CRON_4H=10
MAX_FAILED_HOUR=30
MAX_SCRIPT_HOUR=2
MAX_MS_FORWARD_80S=6
MAX_OUTBOUND_DOMAIN=60

echo ""
read -p "Enter the cPanel username: " CPUSER

if [ -z "$CPUSER" ]; then
    echo "No username entered. Exiting."
    exit 1
fi

# Detect actual home directory dynamically
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

# Temp file for today's log
TODAY_LOG=$(mktemp)
grep "$TODAY" "$LOG" > "$TODAY_LOG"

# Collect all log lines for user's email accounts
USER_LINES=""
for email in $EMAILS; do
    matches=$(grep -F "from=<${email}>" "$TODAY_LOG")
    [ -n "$matches" ] && USER_LINES="$USER_LINES"$'\n'"$matches"
done

if [ -z "$USER_LINES" ]; then
    echo "No outbound activity found for $CPUSER today."
    rm -f "$TODAY_LOG"
    exit 0
fi

# Extract recipient domains
RECIPIENT_DOMAINS=$(echo "$USER_LINES" \
    | grep -oP "to=<[^@]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})>" \
    | sed 's/to=<[^@]\+@//' | sed 's/>//' \
    | sort -u)

echo ""
echo "FOUND DOMAINS SENT TO BY $CPUSER:"

for dom in $RECIPIENT_DOMAINS; do
    count=$(echo "$USER_LINES" | grep "$dom" | wc -l)
    flag=""

    # Apply standard sending limits
    [ "$count" -gt "$MAX_PER_HOUR" ] && flag+=" [EXCEEDS HOURLY MAX $MAX_PER_HOUR]"
    [ "$count" -gt "$MAX_QUEUE" ] && flag+=" [EXCEEDS QUEUE LIMIT $MAX_QUEUE]"
    [[ "$dom" =~ gmail\.com$ ]] && [ "$count" -gt "$GMAIL_LIMIT" ] && flag+=" [EXCEEDS GMAIL RATE $GMAIL_LIMIT/80s]"
    [[ "$dom" =~ yahoo\.com$ ]] && [ "$count" -gt "$YAHOO_LIMIT" ] && flag+=" [EXCEEDS YAHOO RATE $YAHOO_LIMIT/80s]"
    [[ "$dom" =~ (hotmail\.com|live\.com|outlook\.com|microsoft\.com)$ ]] && [ "$count" -gt "$MS_LIMIT" ] && flag+=" [EXCEEDS MS RATE $MS_LIMIT/80s]"

    # Optional extended limits (you can uncomment/use if needed)
    # [ "$count" -gt "$MAX_SPAM_8H" ] && flag+=" [EXCEEDS SPAM 8H MAX $MAX_SPAM_8H]"
    # [ "$count" -gt "$MAX_BULK_8H" ] && flag+=" [EXCEEDS BULK 8H MAX $MAX_BULK_8H]"
    # [ "$count" -gt "$MAX_CRON_4H" ] && flag+=" [EXCEEDS CRON 4H MAX $MAX_CRON_4H]"
    # [ "$count" -gt "$MAX_FAILED_HOUR" ] && flag+=" [EXCEEDS FAILED DELIVERIES $MAX_FAILED_HOUR/H]"
    # [ "$count" -gt "$MAX_SCRIPT_HOUR" ] && flag+=" [EXCEEDS SCRIPT MSGS $MAX_SCRIPT_HOUR/H]"
    # [ "$count" -gt "$MAX_MS_FORWARD_80S" ] && flag+=" [EXCEEDS MS FORWARD $MAX_MS_FORWARD_80S/80s]"
    # [ "$count" -gt "$MAX_OUTBOUND_DOMAIN" ] && flag+=" [EXCEEDS OUTBOUND DOMAIN $MAX_OUTBOUND_DOMAIN]"

    echo "DOMAIN: $dom -> MAX DEFER: $count$flag"
done

rm -f "$TODAY_LOG"
echo ""
