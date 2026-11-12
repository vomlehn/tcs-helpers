#!/bin/sh
# Publishes the packages `make packages` built as a GitHub release.
#
#   release.sh <tag> <notes> <attributions> <deb>... -- <rpm>...
#
# It is tcs-helpers', shared by the TCS projects, and run from its checkout
# by packaging.mk's publish-release target. <tag> is the git tag the release is
# of, which must be pushed already; <notes> a Markdown file of the
# release's notes, written for it; <attributions> the names, separated by
# spaces, of the attributions in packaging/attribution that a licence of
# something compiled into the packages asks to be shown where they are
# downloaded, appended to the notes; and each <deb> and <rpm> a package
# file, named exactly. RELEASE_FLAGS, from the environment, is given to
# gh release create as well, such as --prerelease.
#
# Before anything is published it checks that the tag is on GitHub, that
# no release of it exists, and that every package carries
# THIRD-PARTY-NOTICES, the licence notices of what is compiled into it,
# so that no release goes out without them. A release that exists is left
# alone: replacing its files is gh release upload --clobber's, by hand.
set -eu

if [ $# -lt 4 ]; then
	echo "usage: release.sh <tag> <notes> <attributions> <deb>..." \
	     "-- <rpm>..." >&2
	exit 2
fi
tag=$1
notes=$2
attributions=$3
shift 3
here=$(cd "$(dirname "$0")" && pwd)

# Says what is wrong and what to do, and stops.
#
# Arguments:
#   $@  The message, in as many words as it is given in.
fail() {
	echo "release.sh: $*" >&2
	exit 1
}

command -v gh > /dev/null 2>&1 ||
	fail "gh is not installed: install GitHub's gh and log in with" \
	     "gh auth login, then run make publish-release again"
[ -n "$notes" ] && [ -s "$notes" ] ||
	fail "give RELEASE_NOTES, a Markdown file of the release's notes"
git ls-remote --exit-code --tags origin "refs/tags/$tag" > /dev/null ||
	fail "the tag $tag is not on GitHub: tag the release's commit and" \
	     "run git push origin $tag first"
if gh release view "$tag" > /dev/null 2>&1; then
	fail "a release of $tag exists already: to replace its files, use" \
	     "gh release upload $tag --clobber"
fi

# The package files, each carrying its notices.
files=""
kind=deb
for f in "$@"; do
	if [ "$f" = -- ]; then
		kind=rpm
		continue
	fi
	[ -f "$f" ] || fail "$f is not there: run make packages first"
	if [ $kind = deb ]; then
		list=$(dpkg-deb -c "$f")
	else
		list=$(rpm -qlp "$f" 2> /dev/null)
	fi
	echo "$list" | grep -q '/THIRD-PARTY-NOTICES$' ||
		fail "$f has no THIRD-PARTY-NOTICES: have the project's" \
		     "install-files write it with \$(THIRD_PARTY_NOTICES)"
	files="$files $f"
done
[ -n "$files" ] || fail "there are no packages to publish"

# The notes, and after them each attribution, separated by a rule.
body=$(mktemp)
trap 'rm -f "$body"' EXIT
cat "$notes" > "$body"
for a in $attributions; do
	text=$here/attribution/$a.md
	[ -f "$text" ] ||
		fail "there is no attribution $a: add" \
		     "packaging/attribution/$a.md to tcs-helpers"
	printf '\n\n---\n\n' >> "$body"
	cat "$text" >> "$body"
done

# The files are listed one to a word, and none has a space in its name.
# shellcheck disable=SC2086
gh release create "$tag" --verify-tag --notes-file "$body" \
	${RELEASE_FLAGS:-} $files
