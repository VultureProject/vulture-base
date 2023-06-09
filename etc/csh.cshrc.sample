# $FreeBSD$
#
# System-wide .cshrc file for csh(1).
if ($?prompt) then
    if ( $?tcsh ) then
        bindkey "^W" backward-delete-word
        bindkey -k up history-search-backward
        bindkey -k down history-search-forward
        bindkey "\e[1~" beginning-of-line # Home
        bindkey "\e[7~" beginning-of-line # Home rxvt
        bindkey "\e[2~" overwrite-mode    # Ins
        bindkey "\e[3~" delete-char       # Delete
        bindkey "\e[3;5~" delete-word     # Ctrl Delete
        bindkey "\e[4~" end-of-line       # End
        bindkey "\e[8~" end-of-line       # End rxvt
        bindkey "\e[1;5C" forward-word    # Right arrow
        bindkey "\e[1;5D" backward-word   # Left arrow
    endif
endif
