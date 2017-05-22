#!/usr/bin/env bash

command -v docker-compose > /dev/null
if [[ "$?" != 0 ]]; then
    echo "Install docker-compose first"
    exit 1
fi

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd $SCRIPT_DIR

DEMON=no
WEBSERVER_PORT=5000
PULL=no

while [[ "$#" > 1 ]]; do case $1 in
    --port) WEBSERVER_PORT="$2";;
    --demon) DEMON="$2";;
    --pull) PULL="$2";;
    *) break;;
  esac; shift; shift
done

DOCKERCOMPOSE_FILE=genomics-docker-compose.yml

sudo rm -f $DOCKERCOMPOSE_FILE

cat <<EOT >$DOCKERCOMPOSE_FILE
version: '2'
services:
 postgres:
   image: postgres:9.6.2
   environment:
     - POSTGRES_PASSWORD=postgres
     - POSTGRES_USER=postgres
     - PGDATA=/data
   volumes:
     - ./data/postgres:/data

 redis:
   image: redis:3.0.7

 rabbitmq:
   image: rabbitmq:3-management
   environment:
     - RABBITMQ_DEFAULT_USER=genomix
     - RABBITMQ_DEFAULT_PASS=genomix
   volumes:
     - ./data/rabbitmq/log:/data/log
     - ./data/rabbitmq/data:/data/mnesia

 web:
   image: alapy/genomics_ws:latest
   environment:
     - GEN_WS_DATABASE_PASSWORD=postgres
     - GEN_WS_DATABASE_SERVER=postgres
     - GEN_WS_REDIS_HOST=redis
     - GEN_WS_RABBIT_MQ_HOST=rabbitmq
     - GEN_WS_RABBIT_MQ_USER=genomix
     - GEN_WS_RABBIT_MQ_PASSWORD=genomix
     - GEN_WS_UPLOAD_MAX_SIZE=10000000000000
   volumes:
     - ./data/ws:/data/ws
   depends_on:
     - "rabbitmq"
     - "postgres"
   entrypoint: /bin/bash -c "./wait-for-it.sh rabbitmq:5672 -- ./wait-for-it.sh postgres:5432 -- ./run.sh"
   container_name: genomics_ws
   ports:
    - "$WEBSERVER_PORT:5000"

 as:
   image: alapy/genomics_as:latest
   environment:
     - GEN_BACKEND_RABBITMQ_HOST=rabbitmq
     - GEN_BACKEND_BUCKET=alapy-public
     - GEN_BACKEND_LOG_FILE_PREFIX=/root/AppServer/runtime/as.log
     - GEN_BACKEND_H5_PATH=/data/h5
     - GEN_BACKEND_VCF_PATH=/data/vcf
     - GEN_BACKEND_SOURCE_PATH=/data/sources
     - GEN_BACKEND_VEP_SCRIPT=/root/AppServer/vep_utils/vep_wrapper.pl
   volumes:
     - ./data/as/runtime:/root/AppServer/runtime
     - ./data/vep:/root/.vep
     - ./data/as/data:/data
     - ./data/ws:/data/ws
   depends_on:
     - "rabbitmq"
   entrypoint: /bin/bash -c "./wait-for-it.sh rabbitmq:5672 -- ./main"
EOT

if [ "$PULL" == "yes" ]; then
    sudo docker-compose -f $DOCKERCOMPOSE_FILE pull
    echo "Docker images updated"
    exit
fi

if [ -z "$DEMON" ]; then
    echo "USE --demon start|stop|logs|no"
else
    if [ "$DEMON" == "no" ]; then
        sudo docker-compose -f $DOCKERCOMPOSE_FILE up
    elif [ "$DEMON" == "start" ]; then
        sudo docker-compose -f $DOCKERCOMPOSE_FILE up -d
    elif [ "$DEMON" == "stop" ]; then
        sudo docker-compose -f $DOCKERCOMPOSE_FILE down
    elif [ "$DEMON" == "logs" ]; then
        sudo docker-compose -f $DOCKERCOMPOSE_FILE logs -f
    else
        echo "USE --demon start|stop|logs"
    fi
fi