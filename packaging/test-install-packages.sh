#!/bin/sh
# Tests install-packages.sh's choice of package kind and installer, and its
# refusals, without installing anything.
#
#   test-install-packages.sh
#
# `make check` runs it. Each case gives install-packages.sh an os-release
# file of its own, through TCS_OS_RELEASE, and a PATH holding nothing but
# sed and stand-ins for the installers and sudo, which print the command
# they were given and change nothing; so what is tested is the command
# install-packages.sh would have run on that system, whatever this one
# has installed.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
script=$here/install-packages.sh
env=$(command -v env)
sed=$(command -v sed)

tmp=$(mktemp -d -t tcs-install-test.XXXXXXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/all" "$tmp/apt" "$tmp/dnf" "$tmp/yum" "$tmp/zypper" "$tmp/none"

# A stand-in for an installer, which says what it was asked to do. dnf and
# yum exit 1 under --assumeno, as the real ones do on declining, and rpm -q
# says a package is installed unless FAKE_INSTALLED=no.
standin() {
	cat > "$1/$2" <<EOF
#!/bin/sh
case " \$* " in
" -q "*)
	[ "\${FAKE_INSTALLED:-}" != no ]
	exit
	;;
esac
echo "ran $2 \$*"
case " \$* " in
*" --assumeno "*)
	exit 1
	;;
esac
EOF
	chmod 755 "$1/$2"
}

# Each PATH: every installer, or one, or none, and always sed, sudo and a
# dpkg-query that says a package is installed unless FAKE_INSTALLED=no.
for dir in all apt dnf yum zypper none; do
	ln -s "$sed" "$tmp/$dir/sed"
	cat > "$tmp/$dir/dpkg-query" <<'EOF'
#!/bin/sh
if [ "${FAKE_INSTALLED:-}" = no ]; then
	echo not-installed
else
	echo installed
fi
EOF
	chmod 755 "$tmp/$dir/dpkg-query"
	cat > "$tmp/$dir/sudo" <<'EOF'
#!/bin/sh
echo "as root:"
exec "$@"
EOF
	chmod 755 "$tmp/$dir/sudo"
done
for tool in apt-get dnf yum zypper rpm; do
	standin "$tmp/all" $tool
done
standin "$tmp/apt" apt-get
standin "$tmp/dnf" dnf
standin "$tmp/yum" yum
standin "$tmp/zypper" zypper

osrelease() {
	printf 'ID=%s\nID_LIKE="%s"\n' "$2" "$3" > "$tmp/$1"
}
osrelease ubuntu ubuntu debian
osrelease debian debian ""
osrelease fedora fedora ""
osrelease rocky rocky "rhel centos fedora"
osrelease tumbleweed opensuse-tumbleweed "opensuse suse"
osrelease haiku haiku ""

deb=$tmp/pkg_1.0-1_amd64.deb
rpm=$tmp/pkg-1.0-1.x86_64.rpm
touch "$deb" "$rpm" "$tmp/pkg.deb"
# Where a relative package file is found.
cd "$tmp"

failures=0

# expect <status> <text> <path> <os-release> [VAR=value...] -- <argument>...
# runs install-packages.sh and checks that it exits with <status> and that
# what it prints holds <text>.
expect() {
	want_status=$1
	want=$2
	path=$tmp/$3
	name=$4
	release=$tmp/$4
	shift 4
	vars=
	while [ "$1" != -- ]; do
		vars="$vars $1"
		shift
	done
	shift
	# shellcheck disable=SC2086 # One assignment per word.
	if got=$("$env" -i PATH="$path" TCS_OS_RELEASE="$release" $vars \
	    /bin/sh "$script" "$@" 2>&1); then
		status=0
	else
		status=$?
	fi
	case $got in
	*"$want"*)
		found=1
		;;
	*)
		found=0
		;;
	esac
	if [ "$status" != "$want_status" ] || [ "$found" = 0 ]; then
		echo "FAIL: $name,$vars $*: wanted status $want_status and" \
		     "\"$want\", got status $status and:"
		echo "$got" | sed 's/^/    /'
		failures=$((failures + 1))
	fi
}

# The system's own kind and installer.
expect 0 "ran apt-get install $deb" all ubuntu SUDO=sudo -- \
	install "$deb" -- "$rpm"
expect 0 "as root:" all ubuntu SUDO=sudo -- install "$deb" -- "$rpm"
expect 0 "ran apt-get install $deb" all debian -- install "$deb" -- "$rpm"
expect 0 "ran dnf install $rpm" all fedora -- install "$deb" -- "$rpm"
expect 0 "ran dnf install $rpm" all rocky -- install "$deb" -- "$rpm"
expect 0 "ran yum install $rpm" yum rocky -- install "$deb" -- "$rpm"
expect 0 "ran zypper install $rpm" all tumbleweed -- \
	install "$deb" -- "$rpm"
expect 0 "ran apt-get remove pkg" all ubuntu -- remove pkg
expect 0 "ran dnf remove pkg" all fedora -- remove pkg
expect 0 "ran zypper remove pkg" all tumbleweed -- remove pkg

# Removing what is not installed runs nothing, and is no failure.
expect 0 "pkg is not installed, so there is nothing" all ubuntu \
	FAKE_INSTALLED=no -- remove pkg
expect 0 "pkg is not installed, so there is nothing" all fedora \
	FAKE_INSTALLED=no -- remove pkg

# A relative file is given to apt-get with ./ before it.
expect 0 "ran apt-get install ./pkg.deb" all ubuntu -- \
	install pkg.deb -- "$rpm"

# Simulating: each installer's no-change mode, and never sudo.
expect 0 "ran apt-get install -s $deb" all ubuntu SUDO=sudo DRY_RUN=1 -- \
	install "$deb" -- "$rpm"
expect 0 "[OK] Simulated" all ubuntu SUDO=false DRY_RUN=1 -- \
	install "$deb" -- "$rpm"
expect 0 "ran dnf install --assumeno $rpm" all fedora DRY_RUN=1 -- \
	install "$deb" -- "$rpm"
expect 0 "ran zypper install --dry-run $rpm" all tumbleweed DRY_RUN=1 -- \
	install "$deb" -- "$rpm"
expect 0 "ran apt-get remove -s pkg" all ubuntu DRY_RUN=1 -- remove pkg

# PACKAGE_FORMAT and INSTALLER.
expect 0 "ran dnf install $rpm" all ubuntu PACKAGE_FORMAT=rpm -- \
	install "$deb" -- "$rpm"
expect 0 "ran zypper install $rpm" zypper ubuntu PACKAGE_FORMAT=rpm -- \
	install "$deb" -- "$rpm"
expect 0 "ran apt-get install $deb" all fedora PACKAGE_FORMAT=deb -- \
	install "$deb" -- "$rpm"
expect 0 "ran rpm -U --test $rpm" all ubuntu INSTALLER=rpm DRY_RUN=1 -- \
	install "$deb" -- "$rpm"
expect 0 "ran yum install $rpm" all fedora INSTALLER=yum -- \
	install "$deb" -- "$rpm"
expect 1 "PACKAGE_FORMAT=tgz is neither deb nor rpm" all ubuntu \
	PACKAGE_FORMAT=tgz -- install "$deb" -- "$rpm"
expect 1 "INSTALLER=pacman is not one" all ubuntu INSTALLER=pacman -- \
	install "$deb" -- "$rpm"
expect 1 "make them agree" all ubuntu INSTALLER=dnf PACKAGE_FORMAT=deb -- \
	install "$deb" -- "$rpm"

# What stops it: a system it does not know, an installer that is not
# there, and a package that was not built.
expect 1 "ID=haiku" all haiku -- install "$deb" -- "$rpm"
expect 1 "give PACKAGE_FORMAT=deb or" all haiku -- remove pkg
expect 0 "ran apt-get install $deb" all haiku PACKAGE_FORMAT=deb -- \
	install "$deb" -- "$rpm"
expect 1 "none of dnf, yum and zypper" apt ubuntu PACKAGE_FORMAT=rpm -- \
	install "$deb" -- "$rpm"
expect 1 "dnf, which installs rpm packages here, is not installed" \
	none fedora -- install "$deb" -- "$rpm"
expect 1 "because rpmbuild is not installed" dnf fedora -- \
	install "$deb" -- "$tmp/missing.rpm"
expect 1 "because dpkg-deb is not installed" apt ubuntu -- \
	install "$tmp/missing.deb" -- "$rpm"

if [ "$failures" != 0 ]; then
	echo "test-install-packages.sh: $failures failed" >&2
	exit 1
fi
echo "[OK] install-packages.sh chose as it should in every case"
