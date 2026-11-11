#!/usr/bin/env bash
# The stock generic/non-hostonly Plymouth module can install text.plymouth
# instead of the selected scripted theme. Ensure Astra is actually usable from
# the early initramfs, not only from the immutable root filesystem.
check() {
    [[ -s /usr/share/plymouth/themes/astra-retro-os/astra-retro-os.plymouth ]] &&
    [[ -s /usr/share/plymouth/themes/astra-retro-os/astra-retro-os.script ]]
}

depends() {
    echo plymouth
}

install() {
    local theme_dir=/usr/share/plymouth/themes/astra-retro-os
    local asset plugin
    for asset in astra-retro-os.plymouth astra-retro-os.script \
                 plymouth-splash.png astra-title.png spinner.png; do
        [[ -s "$theme_dir/$asset" ]] || {
            echo "ERROR: Astra Plymouth asset missing: $asset" >&2
            return 1
        }
        inst_simple "$theme_dir/$asset"
    done

    # The script theme needs its renderer plugin, not only its image files.
    plugin=''
    for plugin_candidate in /usr/lib64/plymouth/script.so /usr/lib/plymouth/script.so; do
        if [[ -f "$plugin_candidate" ]]; then
            plugin="$plugin_candidate"
            break
        fi
    done
    [[ -n "$plugin" ]] || { echo 'ERROR: plymouth script.so missing' >&2; return 1; }
    inst "$plugin"

    # The generic Plymouth module may leave a text-only default symlink;
    # replace it in the initramfs only (not on the host).
    mkdir -p "$initdir/usr/share/plymouth/themes"
    ln -sfn astra-retro-os/astra-retro-os.plymouth \
        "$initdir/usr/share/plymouth/themes/default.plymouth"

    if [[ -s /etc/plymouth/plymouthd.conf ]]; then
        inst_simple /etc/plymouth/plymouthd.conf
    fi
}
