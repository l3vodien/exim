#!/bin/sh

RED='\033[0;31m'
GREEN='\033[1;32m'
BLACK='\033[0;30m'


cap1=`date -d 'today' '+%d/%b/%Y:'`
cap2=`date -d 'today' '+%Y-%m-%d'`

EXCEEDED=$(grep 'exceeded the max emails per hour' /var/log/exim_mainlog)

if [[ ! "$EXCEEDED" == "" ]] ; then
echo "Check for exceeded hourly limit - today (last 250 results)"
echo "------------------------------------------------------------------------"
echo -e "$EXCEEDED" | grep "$cap2" | tail -n 250
fi

echo -e ""
echo "Check for email subject (TOP 5) today"
echo "------------------------------------------------------------------------"

grep -wEv 'P=esmtp|P=esmtps'  /var/log/exim_mainlog | grep "$cap2" | awk -F"T=\"" '/<=/ {print $2}' | cut -d\" -f1 | sort | uniq -c | sort -n |  tail -n 5

echo -e ""
echo "Check for number of authentication per account (TOP 5) - today"
echo "------------------------------------------------------------------------"

grep "$cap2" /var/log/exim_mainlog | egrep -o 'dovecot_login[^ ]+' | sort | uniq -c | sort -n | tail -n 5

echo -e ""
echo "check for the number emails sent per cpanel user/directory (TOP 5) today"
echo "------------------------------------------------------------------------"

RESULT=$(grep cwd /var/log/exim_mainlog | grep "$cap2" | grep home | grep -v /var/spool | awk -F"cwd=" '{print $2}' | awk '{print $1}' | sort | uniq -c | sort -n | tail -n 5)

if [[ ! "$RESULT" == "" ]]; then
echo -e "$RESULT"
else
echo -e "non detected"
fi

echo -e ""
echo "Top sender with similiar subjects"
echo "------------------------------------------------------------------------"

SUBJECT=$(echo -e "$RESULT" | awk -F '/' '{print $3}')

if [[ ! "$SUBJECT" == "" ]]; then
echo -e "$SUBJECT" | while read line; do
GET1=$(grep "P=local" /var/log/exim_mainlog | grep "$cap2" | grep "U=$line" | awk -F 'U=' '{print $2}' | awk -F 'T=' '{print $3}' | sort | uniq)
echo -e "${RED}CPANELUSER : $line : *******************************************************${GREEN}"
echo -e "$GET1" | grep -E 'viagra|sidelnafil|generic|women|dutch|' --color
done
else
echo -e "non detected"
fi



TOP3=$(echo "$RESULT" | tail -n 3)

echo -e ""
echo "Suspicious POST request (results shown is only for today)"
echo "------------------------------------------------------------------------"

echo "$TOP3" | while read line ; do
CPANELUSERNAME=$(echo "$line" | awk -F '/' '{print $3}')

RESULT1=$( grep -E -d recurse "$cap1" /usr/local/apache/domlogs/$CPANELUSERNAME/* | grep POST | grep -v admin  | awk '{print $7}' | sort | uniq -c | sort -k1 -n | tail -n 10)
#RESULT1=$(cat /usr/local/apache/domlogs/$CPANELUSERNAME/* | grep -E "$cap1" | grep POST | grep -v admin  | awk '{print $7}' | sort | uniq -c | sort -k1 -n | tail -n 5)

if [[ ! "$RESULT1" == "" ]] ; then
echo -e "CPANELUSER : $CPANELUSERNAME"
echo -e "$RESULT1"
echo -e ""
fi

done

# Max Defers Checker

MAXDEFERS=$(LC_ALL=C grep 'max defers'  /var/log/exim_mainlog | sed '/^$/d')
RESULTS=$(echo -e "$MAXDEFERS" | awk -F 'F=' '{print $2}' | awk '{print $1}' | sort | uniq -c | sed 's/<//g' | sed 's/>//g')

echo
echo "*** Max Defers users Report"
echo
printf "%-16s | %-35s | %-30s\n" "COUNT" "EMAIL" "CPANELUSER"
echo "---------------------------------------------------------------------------"

if [[ ! "$MAXDEFERS" == "" ]]; then
echo -e "$RESULTS" | while read line;do
COUNT=$(echo -e "$line" | awk '{print $1}')
EMAIL=$(echo -e "$line" | awk '{print $2}')
DOMAIN=$(echo -e "$line" | awk '{print $2}' | awk -F "@" '{print $2}')
CPANELUSER=$(/usr/local/cpanel/scripts/whoowns $DOMAIN)
printf "%-16s | %-35s | %-30s\n" $COUNT $EMAIL $CPANELUSER
done
echo "----------------------------------------------------------------------------"
echo
fi


# IP sending details

echo -e "*** IP sending details (Top 20 per email)"
echo
printf "%-16s | %-35s | %-45s | %-30s\n" "IP" "EMAIL" "COUNTRY" "COUNT"
echo "-------------------------------------------------------------------------------------------------------------------"

while read line;do
EMAIL=$(echo -e "$line" | awk '{print $2}')
SMTPLOGS=$(LC_ALL=C grep "$EMAIL" /var/log/exim_mainlog  | grep -E 'esmtpsa|esmtpa')
SMTPCOUNT=$(echo -e "$SMTPLOGS" | awk -F 'I=' '{print $1}' | grep -oP "\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}" | sort  | uniq -c | sort -k1 -n | tail -n 20)


echo -e "$SMTPCOUNT" | grep -v 127.0.0.1 | while read line2; do
COUNT=$(echo -e "$line2" | awk '{print $1}')
IP=$(echo -e "$line2" | awk '{print $2}')
COUNTRY=$(/usr/bin/geoiplookup -d /var/lib/csf/Geo "$IP" | sed -e 's/GeoIP Country Edition://')
printf "%-16s | %-35s | %-45s | %-30s\n" "$IP" "$EMAIL" "$COUNTRY" "$COUNT"
done
echo
done <<<"$RESULTS"

echo "-------------------------------------------------------------------------------------------------------------------"


QUEUESIZE=$(exim -bpc)
echo "-------------------------------------------------------------------------------------------------------------------"
echo -e "Current queue size : $QUEUESIZE"
echo
echo
