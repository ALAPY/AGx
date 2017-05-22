#!/usr/bin/env bash

set -e

while [[ "$#" > 1 ]]; do case $1 in
    --log) LOG="$2";;
    --data-user) DATA_USER="$2";;
    --phase) PHASE="$2";;
    *) break;;
  esac; shift; shift
done

if [ -z "$PHASE" ]; then

    LOG="install-log-$(date +%F-%T)"
    [ -e "$LOG" ] && rm "$LOG"
    touch "$LOG"

    echo "Logging to $LOG"

    sudo "$0" --phase sudo --log "$LOG" --data-user "$USER"

    echo -n "Want to remove zipped data? ('y' or 'Y' for yes)"
    read yn
    if echo "$yn" | grep -iq "^y"; then
        rm vep_bases_88.zip
        rm default_samples_last.zip
        rm genomics_sources.zip
    fi

elif [ "$PHASE" == "sudo" ]; then

    "$0" --phase install --log "$LOG"

    cmd=$(echo "$0" --phase makedirtree --log "$LOG")
    su -c "$cmd" "$DATA_USER"

    "$0" --phase check --log "$LOG"

elif [ "$PHASE" == "install" ]; then

    echo -n "Want to install docker, docker-compose and unzip? ('y' or 'Y' for yes)"
    read yn
    if echo "$yn" | grep -iq "^y"; then

        echo "Updating repos..." | tee $LOG -a

        apt-get update >>$LOG

        echo "Installing utility..." | tee $LOG -a

        apt-get --yes --force-yes install \
            apt-transport-https \
            ca-certificates \
            curl \
            software-properties-common \
            unzip >>$LOG

        echo "Installing docker repo GPG..." | tee $LOG -a

        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - >>$LOG

        echo "Adding docker repo..." | tee $LOG -a

        add-apt-repository \
           "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
           $(lsb_release -cs) \
           stable" >>$LOG

        echo "Updating repos..." | tee $LOG -a

        apt-get update >>$LOG

        echo "Installing docker from 'docker-ce' package..." | tee $LOG -a

        apt-get --yes --force-yes install docker-ce >>$LOG

        if [[ "$?" != 0 ]]; then
            echo "'docker-ce' install failed, trying to install 'docker.io'..." | tee $LOG -a
            apt-get --yes --force-yes install docker.io >>$LOG
        fi

        echo "Downloading docker-compose..." | tee $LOG -a

        curl -L https://github.com/docker/compose/releases/download/1.12.0/docker-compose-$(uname -s)-$(uname -m) > /usr/local/bin/docker-compose

        chmod +x /usr/local/bin/docker-compose

        set +e

        command -v docker > /dev/null
        if [[ "$?" != 0 ]]; then
            echo "'docker' install failed" tee $LOG -a
            exit 1
        fi

        command -v docker-compose > /dev/null
        if [[ "$?" != 0 ]]; then
            echo "'docker-compose' install failed" | tee $LOG -a
            exit 1
        fi

        command -v unzip > /dev/null
        if [[ "$?" != 0 ]]; then
            echo "'unzip' install failed" | tee $LOG -a
            exit 1
        fi

        set -e

    fi

elif [ "$PHASE" == "makedirtree" ]; then

    echo "Making directory tree..." | tee $LOG -a

    mkdir -p data

    mkdir -p data/postgres
    mkdir -p data/rabbitmq

    mkdir -p data/as/data
    mkdir -p data/as/data/h5
    mkdir -p data/as/data/sources
    mkdir -p data/as/data/vcf
    mkdir -p data/as/runtime
    mkdir -p data/as/runtime/genomics_sources

    mkdir -p data/ws

    echo "Downloading data..." | tee $LOG -a

    wget -c -O vep_bases_88.zip http://s3.amazonaws.com/alapy-public/vep_bases_88.zip
    wget -c -O default_samples_last.zip https://s3.amazonaws.com/alapy-public/default_samples_last.zip
    wget -c -O genomics_sources.zip https://s3.amazonaws.com/alapy-public/genomics_sources.zip

    echo "Unpacking data..." | tee $LOG -a

    unzipprogress() {
        zip=$1
        dst=$2
        IFS=$'\n'
        total=$(zipinfo -1 $zip | wc -l)
        current=1
        echo -n "..."
        for z in $(zipinfo -1 $zip); do
            echo -ne "\e[0K\r$zip: $current/$total"
            unzip -o $zip $z -d $dst >>$LOG
            current=$((current+1))
        done
        echo -e "\e[0K\r$zip done.           "
    }

    unzipprogress vep_bases_88.zip data/
    [ -e data/vep ] && rm -r data/vep
    mv data/.vep data/vep
    unzipprogress default_samples_last.zip data/as/data/h5
    unzipprogress genomics_sources.zip data/as/runtime/genomics_sources

    echo "Making directory tree complete" | tee $LOG -a

elif [ "$PHASE" == "check" ]; then

    echo "Updating docker images..."

    ./start-server.sh --pull yes

    echo "Trying to start webserver at 5000..."

    ./start-server.sh --demon start

    until $(curl --output /dev/null --silent --head --fail http://localhost:5000); do printf '.'; sleep 1; done

    echo "Webserver successfully started at 5000, stopping..."

    ./start-server.sh --demon stop

    echo "Webserver successfully installed and tested"

fi
