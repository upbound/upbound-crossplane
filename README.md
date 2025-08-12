# Upbound Crossplane (UXP)
[![docs](https://img.shields.io/badge/📚-docs-blue)](https://docs.upbound.io/manuals/uxp/overview/)
[![Slack](https://img.shields.io/badge/slack-upbound_crossplane-purple?logo=slack)](https://crossplane.slack.com/archives/C01TRKD4623)

<a href="https://upbound.io/uxp">
    <img align="right" style="margin-left: 20px" src="docs/media/logo.png" width=200 />
</a>

Upbound Crossplane (UXP) is the AI-native distribution of [Crossplane](https://docs.crossplane.io/) by Upbound.
Crossplane is a framework for building your own [control plane](https://docs.upbound.io/getstarted/#what-is-upbound).

> [!TIP]
> Upbound Crossplane is a key ingredient in building out a platform powered by an **intelligent control plane architecture**.
> Learn about how UXP safely brings AI intelligence into your control plane's reconcile loop with [Intelligent Controllers](https://docs.upbound.io/manuals/uxp/features/intelligent-controllers/).

## Quick Start

### Installation with the `up` CLI

1. Install the [Upbound CLI][upbound-cli].

   ```console
   curl -sL https://cli.upbound.io | sh
   ```
   
    To install with Homebrew:
    ```console
    brew install upbound/tap/up
    ```

2. Install UXP to a Kubernetes cluster.

   ```console
   # Make sure your ~/.kube/config file points to your cluster
   up uxp install
   ```

### Installation With Helm

1. Add `upbound-stable` chart repository.

   ```console
   helm repo add upbound-stable https://charts.upbound.io/stable && helm repo update
   ```

2. Install the latest stable version of UXP.

   ```console
   helm install crossplane --namespace crossplane-system --create-namespace upbound-stable/crossplane --devel
   ```

> [!NOTE]
> Helm requires the use of `--devel` flag for versions with suffixes, like `v2.0.1-up.1`. The Helm repository Upbound uses
> is the stable repository, so use of that flag is only a workaround. You will always get the latest stable version of
> Upbound Crossplane.

### Upgrade from upstream Crossplane

> [!IMPORTANT]
> **Version Upgrade Rule**: To meet the [upstream Crossplane needs](https://github.com/crossplane/crossplane/discussions/4569#discussioncomment-11836395),
> ensure there is **at most one minor version difference for Crossplane versions** during upgrades.

To upgrade from upstream Crossplane, the target UXP version should match the Crossplane version until the
`-up.N` suffix. You can increment at most one minor version between Crossplane versions to follow
upstream guidelines.

**Examples:**
- ✅ **Allowed**: Crossplane `v2.0.1` → UXP `v2.0.1-up.N` (same Crossplane version)
- ✅ **Allowed**: Crossplane `v2.0.1` → UXP `v2.1.0-up.N` (one minor version diff in Crossplane)
- ✅ **Allowed**: Crossplane `v2.0.1` → UXP `v2.0.5-up.N` (multiple patch versions allowed)
- ❌ **Not allowed**: Crossplane `v2.0.1` → UXP `v2.2.0-up.N` (two minor version diff in Crossplane)

**Required upgrade path for larger Crossplane version gaps:**
If you want to upgrade from Crossplane `v2.0.1` to UXP `v2.2.1-up.N`, follow this incremental approach to meet
upstream requirements:
1. Crossplane `v2.0.1` → UXP `v2.1.0-up.N`
2. UXP `v2.1.0-up.N` → UXP `v2.2.1-up.N`

#### Using up CLI

   ```console
   # Assuming it is installed in "crossplane-system" with release name "crossplane".
   up uxp upgrade -n crossplane-system
   ```

If you'd like to upgrade to a specific version, run the following:

   ```console
   # Assuming it is installed in "crossplane-system" with release name "crossplane".
   up uxp upgrade vX.Y.Z-up.N -n crossplane-system
   ```

#### Using Helm

   ```console
   # Assuming it is installed in "crossplane-system" with release name "crossplane".
   helm upgrade crossplane --namespace crossplane-system upbound-stable/crossplane --devel
   ```

If you'd like to upgrade to a specific version, run the following:

   ```console
   # Assuming it is installed in "crossplane-system" with release name "crossplane".
   helm upgrade crossplane --namespace crossplane-system upbound-stable/crossplane --devel --version vX.Y.Z-up.N
   ```

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md)

## Releases

After each minor Crossplane release, a corresponding patched and hardened
version of Upbound Crossplane will be released after 2 weeks at the latest.

After the minor release of UXP, we will update that version with UXP-specific
patches by incrementing `-up.X` suffix as well as upstream patches by incrementing
the patch version to the corresponding number.

An example timeframe would be like the following:
* Crossplane `v2.0.0` is released.
* 2 weeks bake period.
* The latest version in `release-2.0` is now `v2.0.2`
* The first release of UXP for v2.0 would be `v2.0.2-up.1`.
  * We take the latest patched version at the end of 2 weeks, not `v2.0.0-up.1`
    for example, if there is a patch release.
* Crossplane `v2.0.3` is released after the initial 2 weeks bake period.
* UXP `v2.0.3-up.1` will be released immediately to accommodate the fix coming
  with the patch version.
