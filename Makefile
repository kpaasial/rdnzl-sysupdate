# Path etc. conventions:
# The main binary goes to $PREFIX/bin.
# The individual scripts go to $PREFIX/share/rdnzl-sysupdate.
# Any include files that are not shared with other potential users
# also go to $PREFIX/share/rdnzl-sysupdate.
# Sample .rc file goes to $PREFIX/etc.

PREFIX?=/opt

SCRIPTS= rdnzl-sysupdate 

SHARESCRIPTS= bootstrap.sh buildsources.sh newsources.sh \
	newcleanjail.sh updatebuildjail.sh updatehost.sh 

INCLUDES= sysupdate-common.sh

CONFIGS= rdnzl-sysupdate.rc.sample 

all: ${SCRIPTS} ${CONFIGS} ${INCLUDES}

install: install-scripts install-share-scripts install-configs install-includes

install-scripts: ${SCRIPTS}
	${INSTALL} -d -o root -g wheel ${DESTDIR}${PREFIX}/bin
	${INSTALL} -o root -g wheel -m 755 $> ${DESTDIR}${PREFIX}/bin 

install-share-scripts: ${SHARESCRIPTS}
	${INSTALL} -d -o root -g wheel ${DESTDIR}${PREFIX}/share/rdnzl-sysupdate
	${INSTALL} -o root -g wheel -m 755 $> ${DESTDIR}${PREFIX}/share/rdnzl-sysupdate

install-configs: ${CONFIGS}
	${INSTALL} -d -o root -g wheel ${DESTDIR}${PREFIX}/etc
	${INSTALL} -o root -g wheel -m 444 $> ${DESTDIR}${PREFIX}/etc

install-includes: ${INCLUDES}
	${INSTALL} -d -o root -g wheel ${DESTDIR}${PREFIX}/share/rdnzl-sysupdate
	${INSTALL} -o root -g wheel -m 444 $> ${DESTDIR}${PREFIX}/share/rdnzl-sysupdate

