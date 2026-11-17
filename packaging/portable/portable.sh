#!/bin/sh
# Builds a TCS project's packages on the portable build's system, Ubuntu
# 22.04, in a Podman container, so that they install on systems older than
# the developer's own.
#
#   portable.sh <project> [TARGET...]
#
# It is tcs-helpers', shared by the TCS projects, and run from its checkout
# by packaging.mk's portable-packages target. <project> is the project's
# checkout, and each TARGET a make target to run there, packages when none
# is given. The image, tcs-portable-build, is built from the Containerfile
# beside this the first time, and again with PORTABLE_REBUILD=1, which a
# new Rust or a new build dependency needs.
#
# The directory that holds the project holds the checkouts beside it that
# it is built with, tcs-helpers among them, so that directory is mounted
# at the same path in the container, and the build runs as whoever runs
# this, so that what it writes is theirs. Cargo builds into
# target/portable, apart from the host's target, so that neither build's
# output is taken for the other's; the packages go in build/packages, as
# make packages puts them. Cargo's downloads are kept between builds in
# the volume tcs-portable-cargo. HOME is /tmp, in the container, and pip
# keeps no cache, so that nothing else is left in the project. PODMAN names
# another program than podman.
set -eu

# Prints how to call this command.
usage() {
	echo "usage: portable.sh <project> [TARGET...]"
}

# Says what is wrong and what to do, and stops.
#
# Arguments:
#   $@  The message, in as many words as it is given in.
fail() {
	echo "portable.sh: $*" >&2
	exit 1
}

if [ $# -lt 1 ]; then
	usage >&2
	exit 2
fi
project=$(cd "$1" && pwd) || fail "there is no project at $1"
shift
[ $# -gt 0 ] || set -- packages
here=$(cd "$(dirname "$0")" && pwd)
podman=${PODMAN:-podman}
image=tcs-portable-build
volume=tcs-portable-cargo

command -v "$podman" > /dev/null 2>&1 ||
	fail "$podman is not installed: install Podman (sudo apt-get install" \
	     "podman, or sudo dnf install podman) and run this again"
[ -f "$project/Makefile" ] || fail "$project has no Makefile"

if [ "${PORTABLE_REBUILD:-0}" = 1 ] ||
	! "$podman" image exists "$image"; then
	echo "portable.sh: building the image $image"
	"$podman" build --pull=newer -t "$image" "$here"
fi

workspace=$(dirname "$project")
echo "portable.sh: make $* in $project, on Ubuntu 22.04"
# Every crate of each Cargo workspace the project has, at its top or one
# directory down, is fetched first: third-party-notices.py asks cargo
# metadata about them all, offline, and a build fetches only what it
# compiles. The volume is made the builder's with :U, as keep-id makes
# the builder the user who runs this.
# shellcheck disable=SC2016 # expanded by the container's sh, not here
exec "$podman" run --rm --userns=keep-id \
	--security-opt label=disable \
	-v "$workspace:$workspace" \
	-v "$volume:/cargo:U" \
	-e CARGO_HOME=/cargo \
	-e CARGO_TARGET_DIR="$project/target/portable" \
	-e HOME=/tmp -e PIP_NO_CACHE_DIR=1 \
	-w "$project" \
	"$image" sh -c '
set -e
for lock in Cargo.lock */Cargo.lock; do
	[ -f "$lock" ] || continue
	cargo fetch --locked --quiet --manifest-path "$(dirname "$lock")/Cargo.toml"
done
exec make --no-print-directory "$@"' portable.sh "$@"
