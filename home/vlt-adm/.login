# $FreeBSD: releng/11.2/share/skel/dot.login 325815 2017-11-14 17:05:34Z trasz $
#
# .login - csh login script, read by login shell, after `.cshrc' at login.
#
# See also csh(1), environ(7).
#

# Query terminal size; useful for serial lines.
if ( -x /usr/bin/resizewin ) /usr/bin/resizewin -z