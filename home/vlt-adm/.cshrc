# $FreeBSD$
#
# .cshrc - csh resource script, read at beginning of execution by each shell
#
# see also csh(1), environ(7).
# more examples available at /usr/share/examples/csh/
#

alias h		history 25
alias j		jobs -l
alias la	ls -aF
alias lf	ls -FA
alias ll	ls -laFGh
alias cp	cp -v
alias mv	mv -v
alias rm	rm -v
alias chmod	chmod -v
alias chown	chown -v
alias mkdir	mkdir -vp
alias grep	grep --color=auto
alias admin	/home/vlt-adm/admin.sh

# read(2) of directories may not be desirable by default, as this will provoke
# EISDIR errors from each directory encountered.
# alias grep	grep -d skip


# These are normally set through /etc/login.conf.  You may override them here
# if wanted.
# set path = (/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin $HOME/bin)
# setenv	BLOCKSIZE	K
# A righteous umask
#umask 22

set path = (/sbin /bin /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin $HOME/bin)

setenv	EDITOR	vi
setenv	PAGER	less

if ($?prompt) then
	# An interactive shell -- set some stuff up
	#set prompt = "%N@%m:%~ %# "
	if ( $USER != "root" ) then
		set prompt="(%l)[%{\033[36m%}`whoami`@%{\033[1;30m%}%m:%{\033[0;32m%}%~%{\033[0m%}]%# "
	else
		set prompt="%N@%m:%~ %# "
	endif
	set promptchars = "%#"

	set filec
	set history = 1000
	set savehist = (1000 merge)
	set autolist = ambiguous
	# Use history to aid expansion
	set autoexpand
	set autorehash
	set mail = (/var/mail/$USER)
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

# Reset home directory
cd