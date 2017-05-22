#!/usr/bin/env bash

command -v docker > /dev/null
if [[ "$?" != 0 ]]; then
    echo "Install docker first"
    exit 1
fi

while [[ "$#" > 1 ]]; do case $1 in
    --login) LOGIN="$2";;
    --password) PASSWORD="$2";;
    *) break;;
  esac; shift; shift
done

sudo echo "" > /dev/null

if [ -z "$LOGIN" ]; then
    read -p "Enter login:" LOGIN
fi

sudo docker exec genomics_ws node database/scripts/check-user --email $LOGIN

if [ "$?" == 0 ]; then

    echo "User already registered. Do you want to change its password? ('y' or 'Y' for yes)"
    read yn
    if echo "$yn" | grep -iq "^y"; then
        if [ -z "$PASSWORD" ]; then
            read -s -p "Enter password:" PASSWORD
        fi
        sudo docker exec genomics_ws node database/scripts/add-update-user --firstName user --lastName user --speciality spec --gender gender --company company --numberPaidSamples 10 --defaultLanguage en --loginType password --email "$LOGIN" --password "$PASSWORD" --update 1
    fi

else

    if [ -z "$PASSWORD" ]; then
        read -s -p "Enter password:" PASSWORD
    fi
    sudo docker exec genomics_ws node database/scripts/add-update-user --firstName user --lastName user --speciality spec --gender gender --company company --numberPaidSamples 10 --defaultLanguage en --loginType password --email "$LOGIN" --password "$PASSWORD"

fi