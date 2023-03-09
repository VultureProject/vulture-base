#!/usr/bin/env sh
# Usage update_repositories [prefix_dir]

pkg_url="http://pkg.vultureproject.org/"
vulture_conf="Vulture.conf"
pkg_ca="pkg.vultureproject.org"
update_url="http://updates.vultureproject.org/"
vulture_update_conf="hbsd-update.conf"
vulture_update_ca="ca.vultureproject.org"
temp_dir=$(mktemp -d)

RESET_COLOR="\033[0m"
ORANGE="\033[38;5;172m"

finalize() {
    # set default in case err_code is not specified
    err_code=${1:-0}
    err_message=$2

    if [ -n "$err_message" ]; then
        /bin/echo ""
        /bin/echo "[!] ${err_message}"
        /bin/echo ""
    fi

    /bin/echo "[+] Cleaning temporary dir..."
    /bin/rm -rf "$temp_dir"
    /bin/echo "[-] Done"

    exit $err_code
}

update_repositories() {
    prefix_dir="$1"
    if [ -d ${prefix_dir}/usr/local/etc/pkg/repos/ ]; then
        echo -e "${ORANGE}[!] Disabling custom repos in ${prefix_dir}/usr/local/etc/pkg for the upgrade${RESET_COLOR}"
        echo -e "${ORANGE}[!] Re-enable them manually once the upgrade is finished!${RESET_COLOR}"
        /usr/bin/sed -i '' 's/enabled\(.*\)yes/enabled\1no/' ${prefix_dir}/usr/local/etc/pkg/repos/*.conf
        if [ -e ${prefix_dir}/usr/local/etc/pkg/repos/vulture.conf ]; then
            /bin/mv -f "${prefix_dir}/usr/local/etc/pkg/repos/vulture.conf" "${prefix_dir}/usr/local/etc/pkg/repos/vulture.disabled.conf"
        fi
        /bin/echo "[-] Done"
    fi

    echo -e "${ORANGE}[!] Disabling HardenedBSD default repo, delete ${prefix_dir}/usr/local/etc/pkg/repos/HardenedBSD.disabled.conf to re-enable it${RESET_COLOR}"
    /bin/mkdir -p "${prefix_dir}/usr/local/etc/pkg/repos"
    /bin/echo "HardenedBSD: { enabled: no }" > ${prefix_dir}/usr/local/etc/pkg/repos/HardenedBSD.disabled.conf

    /bin/echo "[*] Backing up default configurations:"
    for conf in ${prefix_dir}/etc/hbsd-update*.conf ; do
        conf=$(basename ${conf})
        if [ ! -f ${prefix_dir}/var/backups/${conf}.bak ]; then
            /bin/echo -n "."
            /bin/mv "${prefix_dir}/etc/$conf" "${prefix_dir}/var/backups/${conf}.bak"
        fi
    done
    /bin/echo "[*] Backups kept at ${prefix_dir}/var/backups/"
    /bin/echo "[-] Done"

    /bin/echo -n "[+] Updating repositories "
    if [ -n "$prefix_dir" ]; then
        /bin/echo "at $prefix_dir"
    else
        /bin/echo "on system"
    fi

    if [ ! -f ${temp_dir}/${vulture_conf} ]; then
        /usr/local/bin/wget -q ${pkg_url}${vulture_conf} --directory-prefix="${temp_dir}" || finalize 1 "[/] Failed to download ${vulture_conf}"
        /bin/echo -n "."
    fi

    /bin/cp -f "${temp_dir}/${vulture_conf}" "${prefix_dir}/etc/pkg/${vulture_conf}"
    /bin/echo -n "."

    if [ ! -f ${temp_dir}/${pkg_ca} ]; then
        /usr/local/bin/wget -q ${pkg_url}${pkg_ca} --directory-prefix="${temp_dir}" || finalize 1 "[/] Failed to download $pkg_ca"
        /bin/echo -n "."
    fi

    /bin/mkdir -p "${prefix_dir}/usr/share/keys/pkg/trusted" && /bin/cp -f "${temp_dir}/${pkg_ca}" "${prefix_dir}/usr/share/keys/pkg/trusted/${pkg_ca}"
    /bin/echo -n "."

    if [ ! -f ${temp_dir}/${vulture_update_conf} ]; then
        /usr/local/bin/wget -q ${update_url}${vulture_update_conf} --directory-prefix="${temp_dir}" || finalize 1  "[/] Failed to download $vulture_update_conf"
        /bin/echo -n "."
    fi

    /bin/mkdir -p "${prefix_dir}/etc" && /bin/cp -f "${temp_dir}/${vulture_update_conf}" "${prefix_dir}/etc/${vulture_update_conf}"
    /bin/echo -n "."

    if [ ! -f ${temp_dir}/${vulture_update_ca} ]; then
        /usr/local/bin/wget -q ${update_url}${vulture_update_ca} --directory-prefix="${temp_dir}" || finalize 1  "[/] Failed to download $vulture_update_ca"
        /bin/echo -n "."
    fi

    /bin/mkdir -p "${prefix_dir}/usr/share/keys/hbsd-update/trusted/" && /bin/cp -f "${temp_dir}/${vulture_update_ca}" "${prefix_dir}/usr/share/keys/hbsd-update/trusted/${vulture_update_ca}"
    /bin/echo "."
}

update_repositories "$1"

finalize
