#!/bin/bash

wget -q https://raw.githubusercontent.com/cotoami/cotoami/develop/launch/docker-compose.yml

if [ -n "$DOCKER_HOST" ]; then
  DOCKER_HOST_IP=$(echo $DOCKER_HOST | sed 's/^.*\/\/\(.*\):[0-9][0-9]*$/\1/g')
else
  DOCKER_HOST_IP=$(docker-machine ip default)
fi

export COMPOSE_PROJECT_NAME=cotoami
export COTOAMI_VERSION=develop
export COTOAMI_HOST=$DOCKER_HOST_IP

docker-compose up -d