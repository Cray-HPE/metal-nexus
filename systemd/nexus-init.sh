#!/bin/bash

# Copyright 2021 Hewlett Packard Enterprise Development LP

# Using sonatype/nexus3:latest introduced an NPE issue with proxying to
# helmrepo.dev.cray.com.
NEXUS_IMAGE="@@sonatype-nexus3-image@@"
NEXUS_IMAGE_PATH="@@sonatype-nexus3-path@@"

command -v podman >/dev/null 2>&1 || { echo >&2 "${0##*/}: command not found: podman"; exit 1; }

if [ $# -lt 2 ]; then
    echo >&2 "usage: nexus-init PIDFILE CIDFILE [CONTAINER [VOLUME]]"
    exit 1
fi

NEXUS_PIDFILE="$1"
NEXUS_CIDFILE="$2"
NEXUS_CONTAINER_NAME="${3-nexus}"
NEXUS_VOLUME_NAME="${4:-${NEXUS_CONTAINER_NAME}-data}"

NEXUS_VOLUME_MOUNT="/nexus-data:rw,exec"

set -x

# Create Nexus volume if not already present
if ! podman volume inspect "$NEXUS_VOLUME_NAME" ; then
    # Load busybox image if it doesn't already exist
    if ! podman image inspect "$NEXUS_IMAGE" >/dev/null; then
        podman load -i "$NEXUS_IMAGE_PATH" "$NEXUS_IMAGE" || exit
    fi
    podman run --rm --network host \
        -v "${NEXUS_VOLUME_NAME}:${NEXUS_VOLUME_MOUNT}" \
        "$NEXUS_IMAGE" /bin/sh -c "
mkdir -p /nexus-data/etc
cat > /nexus-data/etc/nexus.properties << EOF
nexus.onboarding.enabled=false
nexus.scripts.allowCreation=true
nexus.security.randompassword=false
EOF
chown -Rv 200:200 /nexus-data
chmod -Rv u+rwX,go+rX,go-w /nexus-data
" || exit
    podman volume inspect "$NEXUS_VOLUME_NAME" || exit
fi

# always ensure pid file is fresh
rm -f "$NEXUS_PIDFILE"

# Create Nexus container
if ! podman inspect "$NEXUS_CONTAINER_NAME" ; then
    rm -f "$NEXUS_CIDFILE" || exit
    # Load nexus image if it doesn't already exist
    if ! podman image inspect "$NEXUS_IMAGE" >/dev/null; then
        podman load -i "$NEXUS_IMAGE_PATH" "$NEXUS_IMAGE" || exit
    fi
    podman create \
        --conmon-pidfile "$NEXUS_PIDFILE" \
        --cidfile "$NEXUS_CIDFILE" \
        --cgroups=no-conmon \
        -d \
        --network host \
        --volume "${NEXUS_VOLUME_NAME}:${NEXUS_VOLUME_MOUNT}" \
        --name "$NEXUS_CONTAINER_NAME" \
        "$NEXUS_IMAGE" || exit
    podman inspect "$NEXUS_CONTAINER_NAME" || exit
fi
