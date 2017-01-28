#!/bin/sh

set -e
usermod --uid 1000 minecraft
groupmod --gid 1000 minecraft

echo "Switching to user 'minecraft'"
exec sudo -E -u minecraft /start-minecraft "$@"
