#!/usr/bin/env bash

set -Eeuo pipefail


# This script should not be used for "real" releases, for which one should instead
# just use the tag, e.g. 'v1.2.3'
#
# This script uses semver's 'pre-release' syntax to get sortable releases.
# Important to note is that the versions generated are not true 'pre-releases', since
# they use the last tag, which is not indicative of the 'next' release.
# However, as long as one is aware that all pre-releases where the first part ends
# with 'DEV' are dev versions and not pre-releases, this will not be a problem.
#
# For a typical dev build on a branch named 'feat/coolthing' where the last release
# was 'v0.1.0', the final version will look like this:
#
#   v0.1.0-DEV.20250425112514.feat-coolthing.11.sha-3805d7d
#
# This makes it easy to select the type of release/build you want:
#   E.g. when using Flux, one can use the 'semver' range ">= v0.0.0-0"
#   to select any pre-release.
#   Then set the 'semverFilter' to ".*-DEV[.][0-9]+[.]feet-coolthing[.].*$"
#   This will ensure that you always get upgraded to the latest build for
#   your branch.
#
# It also makes it easy to backtrack a running version in your cluster.
#   Say that you see the example version above as the image tag or maybe
#   the Flux OCIRepository source tag. You can quickly deduce that:
#   * It's built on top of the latest release (if you know v0.1.0 is the latest).
#   * It's built from your dev branch (feat/coolthing).
#   * It's probably is/isn't the latest build from looking at the timestamp.
#
# The metadata normally after the '+' sign (replaced here with '.' since '+' is
# not a legal OCI tag character) gives the number of commits since the tag
# was made and the commit short sha, but isn't used for sorting.
#
# References:
# * Semver spec - https://semver.org/
# * Semver library used by Flux - https://github.com/Masterminds/semver
# * Relevant discussions
#   - https://github.com/semver/semver/issues/394
#   - https://github.com/semver/semver/issues/200


# We get the last tag (matching a real vX.X.X version) for semver to work at all.
# If there hasn't been any release made yet, use v0.0.0
last_tag='v0.0.0'
commits_since_last_tag='0'
if git describe --tags --match "v*" --no-abbrev > /dev/null 2>&1; then
  last_tag=$(git describe --tags --match "v*" --no-abbrev 2>/dev/null)

  # Useful metadata for tracking a release back to its commit
  commits_since_last_tag=$(git rev-list ${last_tag}..HEAD --count)
fi

# Useful metadata for tracking a release back to its commit
short_sha=$(git rev-parse --short HEAD)

# We want the branch name to easily select a branch using Flux's 'semverFilter'
current_branch=$(git branch --show-current)
# Only allow alphanumeric and hyphens in 'pre-release' part
# https://semver.org/#spec-item-9
escaped_branch=$(printf "%s" "$current_branch" | sed 's/[^[:alnum:]\-]/-/g')

# The timestamp (and its placement in the final version) is important
# for the semver selector to automatically pick the latest (largest lexicographically)
# version when a new one is pushed. Accurate down to seconds.
timestamp=$(date '+%F%T' | tr -d ':-')
#timestamp=$(date '+%Y%m%d%H%M%S')

# The short sha is prefixed with 'sha-' to prevent invalid version parts, which can
# occur when the sha starts with a zero (0).
final_version=$(printf "%s-DEV.%s.%s.%s.sha-%s" "$last_tag" "$timestamp" "$escaped_branch" "$commits_since_last_tag" "$short_sha")

echo "$final_version"

