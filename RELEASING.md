# Releasing Filippo

This repository ships three release surfaces:

- GitHub Releases for source and daemon artifacts
- npm for `@filippo/cli`
- Homebrew for the full `filippo` install (`filippo` CLI + `filippod` daemon)

## Prerequisites

- GitHub Actions enabled for the repository
- A repository secret named `HOMEBREW_TAP_TOKEN` if you want release automation to update `lucamaraschi/homebrew-tap`
- npm publish access for `@filippo/cli`

## Release Flow

### 1. Verify locally

Run the default checks before tagging:

```bash
make cli-check
make app-check
make app-test
```

### 2. Bump the CLI version

Update the version in:

- `packages/cli/package.json`

If the npm package is being published for the same release, keep this version aligned with the Git tag.

### 3. Create and push a tag

Create an annotated tag:

```bash
git tag -a v0.1.0 -m "filippo v0.1.0"
git push origin v0.1.0
```

The `Release` GitHub Actions workflow will:

- build the CLI bundle
- build the Swift daemon in release mode
- produce release archives
- compute checksums
- render the Homebrew formula
- publish a GitHub Release
- update `lucamaraschi/homebrew-tap` if `HOMEBREW_TAP_TOKEN` is configured

### 4. Publish the CLI to npm

After the GitHub release succeeds:

```bash
cd packages/cli
npm publish --access public
```

### 5. Verify the release artifacts

Check the GitHub Release for:

- `filippo-vX.Y.Z-source.tar.gz`
- `filippod-vX.Y.Z-macos.tar.gz`
- the packed npm tarball
- `checksums.txt`
- `filippo.rb`

If the Homebrew tap automation is enabled, confirm that `lucamaraschi/homebrew-tap` has the updated `Formula/filippo.rb`.

Then verify the user install path:

```bash
brew install lucamaraschi/tap/filippo
filippo --help
filippod --help
```

## Manual Formula Rendering

To render a Homebrew formula manually from a release tarball:

```bash
make release-formula \
  VERSION=0.1.0 \
  RELEASE_URL=https://github.com/lucamaraschi/filippo/releases/download/v0.1.0/filippo-v0.1.0-source.tar.gz \
  SHA256=<source-tarball-sha256>
```

## Notes

- The Homebrew formula builds `filippod` from source on the end user's Mac and installs the bundled CLI at the same time.
- npm remains a separate release surface for users who only want the CLI.
- The daemon requires Accessibility permission on first use.
