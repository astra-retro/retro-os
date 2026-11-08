#!/bin/bash

set -ouex pipefail

cp --archive --verbose --force \
    /tmp/system_files/* \
    /

/ctx/01-install-kernel-akmods.sh
/ctx/02-initialize.sh
/ctx/03-global-remove.sh
/ctx/04-install-packages.sh
/ctx/05-finalize.sh

/ctx/reset-mtimes.sh
