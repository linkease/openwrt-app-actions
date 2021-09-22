#!/bin/sh

rm -rf /opt/docker/hassio

docker run -d --name hassio_supervisor --privileged \
-v /var/run/docker.sock:/var/run/docker.sock \
-v /var/run/dbus:/var/run/dbus \
-v /opt/docker/hassio:/data \
-e SUPERVISOR_SHARE="/opt/docker/hassio" \
-e SUPERVISOR_NAME=hassio_supervisor \
-e HOMEASSISTANT_REPOSITORY="homeassistant/qemuarm-64-homeassistant" \
--restart unless-stopped homeassistant/aarch64-hassio-supervisor
