#!/bin/bash
set -e

# Declare variables
STG_ID=330
TT_DB=$(jq length dashboards.json '.'|xargs)
BKUP_PATH="backup_dashboards"
BKUP_DATE=$(TZ=":Asia/Bangkok" date "+%Y%m%d")
BKUP_TIME=$(TZ=":Asia/Bangkok" date "+%H%M")

# Get Staging JSON Dashboard
echo "Getting dashboard(s) from STAGING in process..."
DB_PATH_LIST=$(git whatchanged -p -1|grep '+++ b/'|grep $BKUP_PATH|grep .dashboard.lookml|cut -d '/' -f2-)
i=0
count_check=0
while [ $i -le $TT_DB ]; do
	for DB_PATH in $DB_PATH_LIST; do
		FD=$(echo $DB_PATH|cut -d '/' -f3)
		DB_NAME=$(head -n 2 ./$DB_PATH|grep title:|cut -d " " -f 4-)
		if [[ ! -d ./$(echo $DB_PATH|cut -d '/' -f1-3)/json_staging  ]]; then
			mkdir -p ./$(echo $DB_PATH|cut -d '/' -f1-3)/json_staging 
		fi
		if [[ $(jq '.['$i'].space.parent_id' dashboards.json|xargs) == $STG_ID && $(jq '.['$i'].title' dashboards.json|xargs) = $DB_NAME && $(jq '.['$i'].space.name' dashboards.json|tr "[:upper:]" "[:lower:]"|tr ' ' '_'|xargs) = $(echo $DB_PATH|cut -d '/' -f2) ]]; then
			echo "Exporting '"$DB_NAME"' from staging-"$(jq '.['$i'].space.name' dashboards.json|tr ' ' '_'|xargs)", prod folder is "$FD"..." 
			gzr dashboard cat $(jq '.['$i'].id' dashboards.json|xargs) --host crea.cloud.looker.com --client-id=$CLIENT_ID --client-secret=$CLIENT_SECRET --dir=./$(echo $DB_PATH|cut -d '/' -f1-3)/json_staging/ --simple-filename
			((count_check+=1))
			if [[ $count_check == $(echo $DB_PATH_LIST|tr ' ' '\n'|wc -l|xargs) ]]; then
				echo ""
				break 2
			fi
		fi
	done
	((i+=1))
done
rm dashboards.json

# Get Production JSON Dashboards for backup
echo "Backup in process..."
for DB_PATH in $DB_PATH_LIST; do
	DB_NAME=$(head -n 2 ./$DB_PATH|grep title:|cut -d " " -f 4-)
	DB_ID=$(echo $DB_PATH|cut -d '/' -f4|cut -d '.' -f1|cut -d '_' -f1)
	FD=$(echo $DB_PATH|cut -d '/' -f3)
	# FD_ID=$(echo $DB_PATH|cut -d '/' -f2|cut -d '_' -f1|xargs)
	if [[ ! -d ./$(echo $DB_PATH|cut -d '/' -f1-3)/json_prod_bkup  ]]; then
		mkdir -p ./$(echo $DB_PATH|cut -d '/' -f1-3)/json_prod_bkup
	fi
	echo "Exporting '"$DB_NAME"' from folder "$FD"..." 
	gzr dashboard cat $DB_ID --host crea.cloud.looker.com --client-id=$CLIENT_ID --client-secret=$CLIENT_SECRET --dir=./$(echo $DB_PATH|cut -d '/' -f1-3)/json_prod_bkup/ --simple-filename
done

# Remove Dashboard Slug
sed -e '11d' -n ./$BKUP_PATH/*/*/json_*/Dashboard_*.json

#Backup Process
git config --global user.name "$GH_USERNAME"
git config --global user.email "<>"
git add ./$BKUP_PATH/*/*/json_prod_bkup/*
git commit -m "Backup dashboard $(cat ./$BKUP_PATH/*/*/json_prod_bkup/*.json|jq '.title')" .
git tag bkup.$BKUP_DATE.$BKUP_TIME
git push origin --tags

# Deployment
echo "Start deploying..."
for DB_PATH in $DB_PATH_LIST; do
	for JSON_PATH in $(ls -d ./$(echo $DB_PATH|cut -d '/' -f1-3)/json_staging/*.json); do
		if [[ $(echo $DB_PATH|cut -d '/' -f2) = $(jq '.space.name' ./$JSON_PATH|tr "[:upper:]" "[:lower:]"|tr ' ' '_'|xargs) ]]; then
			gzr dashboard import $JSON_PATH $(echo $DB_PATH|cut -d '/' -f3|cut -d '_' -f1) --host crea.cloud.looker.com --client-id=$CLIENT_ID --client-secret=$CLIENT_SECRET --force
		fi
	done
done
