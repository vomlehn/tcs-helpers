#!/bin/sh
# Installs the packages `make packages` built, or removes them, with the
# installer this system's own packages are installed with.
#
#   install-packages.sh install <deb>... -- <rpm>...
#   install-packages.sh remove <package>...
#
# It is tcs-helpers', shared by the TCS projects, and run from its checkout
# by packaging.mk's install and uninstall targets. Each <deb> and <rpm> is
# a package file, named exactly, so that a stale one left beside it is
# never installed; install installs those of the one kind this system
# takes. Each <package> is a package's name.
#
# The kind and the installer are chosen from the ID and ID_LIKE of
# /etc/os-release, which say what the system is, rather than from which
# tools are present, since a Debian system may have rpm installed and an
# RPM one dpkg:
#
#   debian, ubuntu                      .deb, with apt-get
#   fedora, rhel, centos, rocky,        .rpm, with dnf, or yum without it
#   almalinux
#   suse, opensuse*, sles               .rpm, with zypper
#
# apt-get rather than dpkg -i, and dnf rather than rpm -U, because they
# also install what the package depends on. These, from the environment,
# change that:
#
#   PACKAGE_FORMAT  deb or rpm, the kind to install whatever the system
#                   is, with its usual installer if the system has one,
#                   and otherwise the first of dnf, yum and zypper found
#   INSTALLER       the installer to run: apt-get, apt, dpkg, dnf, yum,
#                   zypper or rpm, or a path to one; its kind is the
#                   package kind, unless PACKAGE_FORMAT says otherwise
#   SUDO            the command the installer is run under, by default
#                   none; packaging.mk gives sudo unless make runs as
#                   root, so that only the installer is privileged
#   DRY_RUN         1 to run the installer's own mode that shows what it
#                   would do and changes nothing (apt-get -s, dnf and yum
#                   --assumeno, zypper --dry-run, rpm --test, dpkg
#                   --dry-run), without SUDO
#   TCS_OS_RELEASE  the os-release file to read instead of the system's,
#                   for testing
#
# Nothing here builds anything: a package file that is not there stops it,
# naming the tool whose absence kept it from being built. remove removes
# only the packages that are installed, saying so of the rest, so that
# uninstalling twice is no failure.
set -eu

usage() {
	echo "usage: install-packages.sh install <deb>... -- <rpm>..." >&2
	echo "       install-packages.sh remove <package>..." >&2
	exit 2
}

if [ $# -lt 1 ]; then
	usage
fi
action=$1
shift
case $action in
install|remove)
	;;
*)
	usage
	;;
esac

PACKAGE_FORMAT=${PACKAGE_FORMAT:-}
INSTALLER=${INSTALLER:-}
SUDO=${SUDO:-}
DRY_RUN=${DRY_RUN:-}

# One field of the os-release file, without the quotes it may have. It is
# read rather than sourced, so that the file is data and never run.
os_field() {
	sed -n "s/^$1=//p" "$os_release" | sed -e 's/^"//' -e 's/"$//' \
		-e "s/^'//" -e "s/'\$//"
}

# What the system is, from os-release: the family whose installer it uses,
# deb-apt, rpm-dnf or rpm-zypper, or nothing for one not known here. ID is
# looked at first, then each word of ID_LIKE in turn, which is how
# os-release says to read them.
os_release=${TCS_OS_RELEASE:-}
if [ -z "$os_release" ]; then
	if [ -r /etc/os-release ]; then
		os_release=/etc/os-release
	else
		os_release=/usr/lib/os-release
	fi
fi
if [ -r "$os_release" ]; then
	os_id=$(os_field ID)
	os_like=$(os_field ID_LIKE)
else
	os_id=
	os_like=
fi
family=
for word in $os_id $os_like; do
	case $word in
	debian|ubuntu)
		family=deb-apt
		;;
	fedora|rhel|centos|rocky|almalinux)
		family=rpm-dnf
		;;
	suse|opensuse|opensuse-*|sles|sled)
		family=rpm-zypper
		;;
	esac
	if [ -n "$family" ]; then
		break
	fi
done

have() {
	command -v "$1" > /dev/null 2>&1
}

# The kind of package an installer takes.
installer_format() {
	case ${1##*/} in
	apt-get|apt|dpkg)
		echo deb
		;;
	dnf|dnf5|yum|zypper|rpm)
		echo rpm
		;;
	*)
		echo "install-packages.sh: INSTALLER=$1 is not one this knows" \
		     "how to run: give apt-get, apt, dpkg, dnf, yum, zypper" \
		     "or rpm" >&2
		exit 1
		;;
	esac
}

case $PACKAGE_FORMAT in
''|deb|rpm)
	;;
*)
	echo "install-packages.sh: PACKAGE_FORMAT=$PACKAGE_FORMAT is" \
	     "neither deb nor rpm: give one of them, or leave it unset" \
	     "for this system's own" >&2
	exit 1
	;;
esac

# The kind: as PACKAGE_FORMAT says, or as INSTALLER takes, or the system's.
# INSTALLER is checked first whatever the kind, so that one this does not
# know is named as the problem.
installer_kind=
if [ -n "$INSTALLER" ]; then
	installer_kind=$(installer_format "$INSTALLER")
fi
format=${PACKAGE_FORMAT:-$installer_kind}
if [ -z "$format" ]; then
	format=${family%%-*}
fi
if [ -z "$format" ]; then
	echo "install-packages.sh: make install and make uninstall do not" \
	     "know how packages are installed on this system, whose" \
	     "${os_release} says ID=${os_id:-(none)}" \
	     "ID_LIKE=${os_like:-(none)}: give PACKAGE_FORMAT=deb or" \
	     "PACKAGE_FORMAT=rpm, and INSTALLER=<command> if its installer" \
	     "is not apt-get, dnf, yum or zypper, or copy the files into" \
	     "place with make install-files" >&2
	exit 1
fi

# The installer: as INSTALLER says, or the system's own for the kind, or,
# for a kind the system does not use, the first installer of it present.
installer=$INSTALLER
if [ -z "$installer" ]; then
	case $format-$family in
	deb-*)
		installer=apt-get
		;;
	rpm-rpm-zypper)
		installer=zypper
		;;
	rpm-rpm-dnf)
		installer=dnf
		if ! have dnf && have yum; then
			installer=yum
		fi
		;;
	rpm-*)
		installer=
		for candidate in dnf yum zypper; do
			if have $candidate; then
				installer=$candidate
				break
			fi
		done
		if [ -z "$installer" ]; then
			echo "install-packages.sh: none of dnf, yum and zypper," \
			     "which install rpm packages, is installed here:" \
			     "install one, or name the installer to use with" \
			     "INSTALLER=<command>, such as INSTALLER=rpm" >&2
			exit 1
		fi
		;;
	esac
fi
if [ -n "$installer_kind" ] && [ "$installer_kind" != "$format" ]; then
	echo "install-packages.sh: INSTALLER=$INSTALLER installs" \
	     "$installer_kind packages, not the" \
	     "$format ones PACKAGE_FORMAT asks for: make them agree, or" \
	     "give only one" >&2
	exit 1
fi
if ! have "$installer"; then
	echo "install-packages.sh: $installer, which installs $format" \
	     "packages here, is not installed: install it, or name the" \
	     "installer to use with INSTALLER=<command>" >&2
	exit 1
fi

# The package files of the kind chosen, each of which must be there.
if [ "$action" = install ]; then
	debs=
	rpms=
	while [ $# -gt 0 ] && [ "$1" != -- ]; do
		debs="$debs $1"
		shift
	done
	if [ $# -gt 0 ]; then
		shift
	fi
	rpms=$*
	if [ "$format" = deb ]; then
		files=$debs
		builder=dpkg-deb
		builder_hint="the dpkg-dev package"
	else
		files=$rpms
		builder=rpmbuild
		builder_hint="sudo dnf install rpm-build, sudo zypper"
		builder_hint="$builder_hint install rpm-build or sudo"
		builder_hint="$builder_hint apt-get install rpm"
	fi
	if [ -z "$files" ]; then
		echo "install-packages.sh: there are no $format packages" \
		     "to install" >&2
		exit 2
	fi
	for file in $files; do
		if [ -f "$file" ]; then
			continue
		fi
		if ! have $builder; then
			echo "install-packages.sh: $file was not built," \
			     "because $builder is not installed: install it" \
			     "($builder_hint) and run make install again" >&2
		else
			echo "install-packages.sh: $file is not there," \
			     "though make packages ran: run make packages" \
			     "and see what it says" >&2
		fi
		exit 1
	done
	# apt-get takes a word as a file only when it has a slash in it.
	args=
	for file in $files; do
		case $file in
		*/*)
			args="$args $file"
			;;
		*)
			args="$args ./$file"
			;;
		esac
	done
else
	if [ $# -eq 0 ]; then
		usage
	fi
	# Only the packages that are installed, so that uninstalling what is
	# not installed, or no longer, is no failure: apt-get and zypper fail
	# on a package they do not know.
	args=
	for package in "$@"; do
		if [ "$format" = deb ]; then
			status=$(dpkg-query -W -f '${db:Status-Status}' \
				"$package" 2>/dev/null || true)
			[ "$status" = installed ] || status=
		elif rpm -q "$package" > /dev/null 2>&1; then
			status=installed
		else
			status=
		fi
		if [ -n "$status" ]; then
			args="$args $package"
		else
			echo "$package is not installed, so there is nothing of" \
			     "it to remove"
		fi
	done
	if [ -z "$args" ]; then
		exit 0
	fi
fi

# The installer's command for the action, and its no-change mode.
simulate=
case ${installer##*/}-$action in
apt-get-install|apt-install)
	command="install"
	simulate=-s
	;;
apt-get-remove|apt-remove)
	command="remove"
	simulate=-s
	;;
dnf-install|dnf5-install|yum-install)
	command="install"
	simulate=--assumeno
	;;
dnf-remove|dnf5-remove|yum-remove)
	command="remove"
	simulate=--assumeno
	;;
zypper-install)
	command="install"
	simulate=--dry-run
	;;
zypper-remove)
	command="remove"
	simulate=--dry-run
	;;
rpm-install)
	command="-U"
	simulate=--test
	;;
rpm-remove)
	command="-e"
	simulate=--test
	;;
dpkg-install)
	command="-i"
	simulate=--dry-run
	;;
dpkg-remove)
	command="-r"
	simulate=--dry-run
	;;
esac

if [ "$DRY_RUN" = 1 ]; then
	echo "Simulating, which changes nothing:"
	echo "  $installer $command $simulate$args"
	# shellcheck disable=SC2086 # One file or package per word.
	if "$installer" $command $simulate $args; then
		status=0
	else
		status=$?
	fi
	# dnf and yum show the transaction --assumeno declines, and then
	# exit 1 for declining it, as they do for a transaction that cannot
	# be made, so the status says nothing here: their output does.
	case ${installer##*/} in
	dnf|dnf5|yum)
		if [ "$status" = 1 ]; then
			echo "($installer exits 1 after declining, as" \
			     "--assumeno has it do: the lines above say" \
			     "whether it could have gone ahead)"
			status=0
		fi
		;;
	esac
	if [ "$status" = 0 ]; then
		echo "[OK] Simulated: nothing was installed or removed"
	fi
	exit "$status"
fi

echo "  ${SUDO:+$SUDO }$installer $command$args"
# shellcheck disable=SC2086 # SUDO may be a command and its options.
$SUDO "$installer" $command $args
if [ "$action" = install ]; then
	echo "[OK] Installed with $installer"
else
	echo "[OK] Removed with $installer"
fi
