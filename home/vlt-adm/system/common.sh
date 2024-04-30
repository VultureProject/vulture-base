#!/usr/bin/env sh

COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW="\033[1;33m"
TEXT_BLINK='\033[5m'


# If "NO_COLOR" environment variable is present, or we aren't speaking to a
# tty, disable output colors.
if [ -n "${NO_COLOR}" ] || [ ! -t 1 ]; then
    COLOR_RESET=''
    COLOR_RED=''
    COLOR_YELLOW=''
    TEXT_BLINK=''
fi

warn() {
        /usr/bin/printf "${COLOR_YELLOW}$*${COLOR_RESET}\n"
}

error() {
        /usr/bin/printf "${COLOR_RED}$*${COLOR_RESET}\n" 1>&2
}

error_and_blink() {
        /usr/bin/printf "${COLOR_RED}${TEXT_BLINK}$*${COLOR_RESET}\n" 1>&2
}