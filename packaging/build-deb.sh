#!/bin/sh
# Builds one .deb from the tree `make stage` installed that package into.
#
#   build-deb.sh <debdir> <source> <package> <stage> <work> <out> <version>
#                <arch> <epoch>
#
# It is tcs-helpers', shared by the TCS projects, and run from its checkout
# by packaging.mk's deb target, once per package. <debdir> is the project's
# packaging/deb directory, which holds <package>/DEBIAN, the package's
# control file and maintainer scripts, as well as what debian-files.sh
# reads; <source> is the project's repository name, the source package's;
# <package> the package being built; <stage> the directory `make stage`
# installed it into, by itself; <work> a directory this may fill and empty;
# <out> where the .deb goes; <version> the Debian version, upstream and
# revision; <arch> what `dpkg --print-architecture` says; and <epoch> the
# release's time in seconds since 1970, which dates its changelog entry.
#
# In <package>/DEBIAN/control, @VERSION@, @ARCH@, @SIZE@ and @SHLIBS@ are
# replaced by the version, the architecture, the installed size in KiB and
# the packages holding the shared libraries the package links with. The
# maintainer scripts there, preinst, postinst, prerm and postrm, are copied
# as they are.
#
# Without a debian/ tree, because the packages are cut from what `make
# install` puts in place rather than built by debhelper: the stage is the one
# account of what is installed where, and a second one in debian/ would be a
# second list to keep right.
set -eu

if [ $# -ne 9 ]; then
	echo "usage: build-deb.sh <debdir> <source> <package> <stage> <work>" \
	     "<out> <version> <arch> <epoch>" >&2
	exit 2
fi
debdir=$1
source=$2
package=$3
stage=$4
work=$5
out=$6
version=$7
arch=$8
epoch=$9

here=$(dirname "$0")
template=$debdir/$package/DEBIAN
root=$work/$package

if [ ! -f "$template/control" ]; then
	echo "build-deb.sh: there is no $template/control" >&2
	exit 1
fi

rm -rf "$root"
mkdir -p "$root" "$out"
cp -a "$stage/." "$root/"
mkdir "$root/DEBIAN"

# The shared libraries the package's programs and libraries are linked with,
# as the packages that hold them. dpkg-shlibdeps reads debian/control, which
# a package built without a debian/ tree does not have, so it is given one
# that names this package and says nothing else.
elves=$(find "$root" -path "$root/DEBIAN" -prune -o -type f -print |
	while read -r file; do
		if [ "$(head -c 4 "$file" | od -An -c | tr -d ' ')" = 177ELF ]
		then
			echo "$file"
		fi
	done)
if [ -z "$elves" ]; then
	echo "build-deb.sh: $package has no programs or libraries in it:" \
	     "run make stage first" >&2
	exit 1
fi
shlibs=$work/shlibdeps-$package
rm -rf "$shlibs"
mkdir -p "$shlibs/debian"
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$source" \
	"$package" > "$shlibs/debian/control"
# shellcheck disable=SC2086 # One ELF file per word.
depends=$(cd "$shlibs" && dpkg-shlibdeps -O -l"$root/opt/tcs/lib" $elves |
	sed -n 's/^shlibs:Depends=//p')
if [ -z "$depends" ]; then
	echo "build-deb.sh: dpkg-shlibdeps found no dependencies for" \
	     "$package, which links with libc at least" >&2
	exit 1
fi

size=$(du -sk --exclude=DEBIAN "$root" | cut -f1)
sed -e "s|@VERSION@|$version|g" -e "s|@ARCH@|$arch|g" \
    -e "s|@SIZE@|$size|g" -e "s|@SHLIBS@|$depends|g" \
	"$template/control" > "$root/DEBIAN/control"

for script in preinst postinst prerm postrm; do
	if [ -f "$template/$script" ]; then
		install -m 755 "$template/$script" "$root/DEBIAN/$script"
	fi
done

# A shlibs entry for each shared library the package holds under its
# soname, so that a package built against one -- with dpkg-shlibdeps -l
# /opt/tcs/lib -- depends on this package at this version or later. Found
# from the files, as the conffiles are, rather than listed.
for library in "$root"/opt/tcs/lib/lib*.so.[0-9]*; do
	[ -f "$library" ] || continue
	soname=${library##*/}
	echo "${soname%%.so.*} ${soname##*.so.} $package (>= ${version%-*})"
done > "$work/shlibs-$package"
if [ -s "$work/shlibs-$package" ]; then
	install -m 644 "$work/shlibs-$package" "$root/DEBIAN/shlibs"
fi

# Every file under /etc is a conffile, so that an upgrade never overwrites
# one somebody has edited. Found rather than listed, so that a hook added to
# `make install` is a conffile without a second list to remember it in.
if [ -d "$root/etc" ]; then
	(cd "$root" && find etc -type f | sed 's|^|/|' | sort) \
		> "$root/DEBIAN/conffiles"
	chmod 644 "$root/DEBIAN/conffiles"
fi

# What Debian expects outside /opt/tcs and the RPM does not have: the
# copyright file, the Debian changelog, the lintian overrides, the trigger
# that runs ldconfig and the md5sums. See debian-files.sh.
"$here/debian-files.sh" "$debdir" "$source" "$package" "$root" \
	"$version" "$epoch"

dpkg-deb --root-owner-group --build "$root" \
	"$out/${package}_${version}_${arch}.deb"
