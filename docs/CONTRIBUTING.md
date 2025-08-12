# Contributing

## Developer Guide

### Local Development

To spin up a local development environment with locally built artifacts, run:

```
make local-dev
```

### Cleanup

To clean up local dev environment, first delete self hosted control plane (if connected) from Upbound Cloud Console
and then run:

```
make local-dev.down
```

### Validation

To run validation tests locally, run:

```
make e2e.run
```

## Release Process

### Crossplane fork sync:

To update Crossplane version in UXP follow the steps below:

#### Prepare repos and forks

All the steps below will assume you have forked the following repos with the following names:

- upstream Crossplane: `crossplane/crossplane` -> `$MY_GITHUB_USER/crossplane`
- Upbound Crossplane's fork `upbound/crossplane` -> `$MY_GITHUB_USER/upbound-crossplane`

Once you have created them, you'll need to setup your local environment, if you
already did it in the past just skip to the next part, otherwise run the
following commands, taking care to set your GitHub user instead of
`<MY_GITHUB_USER>`:

```shell
export MY_GITHUB_USER=<MY_GITHUB_USER>

mkdir sync-upbound-crossplane
cd sync-upbound-crossplane
git clone https://github.com/$MY_GITHUB_USER/crossplane
cd crossplane
git remote add upstream https://github.com/crossplane/crossplane
git remote add upbound-upstream https://github.com/upbound/crossplane
git remote add upbound-origin https://github.com/$MY_GITHUB_USER/upbound-crossplane
git fetch --all
```

Now based on the task at hand, pick and go through one of the task below:

##### Create **a new** release branch:

If you are releasing a new minor of UXP, e.g. `vX.Y.0-up.1`, and you want to
create a new release branch `release-X.Y` on `upbound/crossplane` based on the
upstream `crossplane/crossplane` release branch.

> [!IMPORTANT]
> First, make sure to have updated the main branch, see [section below](#sync-latest-main).

```shell
RELEASE_BRANCH=release-X.Y
RELEASE_TAG=vX.Y.0

git fetch --all

# Create the new release branch from the one on crossplane/crossplane.
git checkout -b $RELEASE_BRANCH upstream/$RELEASE_BRANCH
git diff --exit-code && git reset --hard $RELEASE_TAG # or whatever version we are releasing

# Push it to upbound/crossplane, creating the new release branch.
git push upbound-upstream $RELEASE_BRANCH

# Create/update the sync-upstream-main branch
git checkout sync-upstream-main || git checkout -b sync-upstream-main

git reset --hard upbound-upstream/main
git merge upstream/main
# Resolve conflicts, if any

# Now we have the latest main branch + our changes in sync-upstream-main
# branch. Take a diff of the two branches and apply it to the release branch.
git checkout -b patch-$RELEASE_BRANCH $RELEASE_BRANCH
git diff upstream/main upbound-upstream/main | git apply -3
# Resolve conflicts, if any
# Ensure code builds and tests pass
# go mod tidy
# earthly +reviewable
# commit all changes
git commit -s -m "Apply upbound patches"

# Push the release branch to upbound/crossplane
git push --set-upstream upbound-origin patch-$RELEASE_BRANCH

# Open a PR from patch-$RELEASE_BRANCH to $RELEASE_BRANCH
```

##### Sync **an existing** release branch:

If you are releasing a new patch of UXP, e.g. `vX.Y.Z-up.1`, and you want to
open a PR to update `release-X.Y` on `upbound/crossplane` with the latest
changes up to `vX.Y.Z` of upstream `crossplane/crossplane`.

```shell
RELEASE_BRANCH=release-X.Y
UPSTREAM_RELEASE_TAG=vX.Y.Z

git checkout -b sync-upstream-$RELEASE_BRANCH
git reset --hard upbound-upstream/$RELEASE_BRANCH
git fetch --tags upstream
git merge $UPSTREAM_RELEASE_TAG

# Resolve conflicts, if any, and then push to your own fork
git push --set-upstream upbound-origin sync-upstream-$RELEASE_BRANCH
```

You can then create a PR from your fork's `sync-upstream-X.Y` branch to
`upbound/crossplane`'s `release-X.Y` branch and get it reviewed and merged.

##### Sync latest main:

This step is not required at the moment, but if you want to sync
`upbound/crossplane`'s main branch to the latest `crossplane/crossplane`
branch, run the following commands and open a PR from your fork's `sync-upstream-main` branch to
`upbound/crossplane`'s `main` branch and get it reviewed and merged.

```shell
git fetch --all
git checkout -b sync-upstream-main
git reset --hard upbound-upstream/main
git merge upstream/main
# Resolve conflicts, if any
git push --set-upstream upbound-origin sync-upstream-main
```

