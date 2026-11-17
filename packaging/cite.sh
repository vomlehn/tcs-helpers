#!/bin/sh
# Brings a project's CITATION.cff to a release: the version it cites, and
# the date it was released.
#
#   cite.sh <tag>
#
# It is tcs-helpers', shared by the TCS projects, and run from the top of
# the project's work tree: by release.sh, once a release is published, or
# by hand. <tag> is the release's git tag, v and a version, such as v1.2.0.
#
# The version is the tag's without its v, and the date today's, in UTC, as
# GitHub dates a release. Where that changes the file, it is committed,
# alone, on the branch checked out, and pushed, so that GitHub's "Cite this
# repository" names the latest release. A project without a CITATION.cff,
# a prerelease (RELEASE_FLAGS, from the environment, holding --prerelease)
# and a tag that is not v and a version leave everything as it is.
set -eu

# Prints how to call this command.
usage() {
	echo "usage: cite.sh <tag>"
}

# Says what is wrong and what to do, and stops.
#
# Arguments:
#   $@  The message, in as many words as it is given in.
fail() {
	echo "cite.sh: $*" >&2
	exit 1
}

if [ $# -ne 1 ]; then
	usage >&2
	exit 2
fi
tag=$1
file=CITATION.cff

[ -f "$file" ] || exit 0
case " ${RELEASE_FLAGS:-} " in
*" --prerelease "*)
	exit 0
	;;
esac
case $tag in
v[0-9]*.[0-9]*.[0-9]*) ;;
*)
	exit 0
	;;
esac
version=${tag#v}
today=$(date -u +%Y-%m-%d)

if ! grep -q '^version: ' "$file" ||
	! grep -q '^date-released: ' "$file"; then
	fail "$file has no version: or no date-released: line to bring to" \
	     "$version: add both"
fi
git diff --quiet HEAD -- "$file" ||
	fail "$file has changes that are not committed: commit or drop them," \
	     "then run cite.sh $tag again"

sed -i -e "s/^version: .*/version: $version/" \
	-e "s/^date-released: .*/date-released: $today/" "$file"
if git diff --quiet -- "$file"; then
	exit 0
fi
branch=$(git symbolic-ref --quiet --short HEAD) || {
	git checkout -- "$file"
	fail "no branch is checked out, so $file cannot be committed:" \
	     "check out the release's branch and run cite.sh $tag again"
}
git commit -q -m "Cite $version in $file" \
	-m "The citation names the release $tag, published $today." -- "$file"
git push -q origin "$branch" ||
	fail "$file is committed for $version but could not be pushed:" \
	     "run git push origin $branch"
echo "cite.sh: $file cites $version, released $today, on $branch"
