# Plank Nix Flake

Standalone Nix flake for [Plank](https://github.com/plankevm/plank-monorepo).

This repository packages Plank from the upstream `plankevm/plank-monorepo` source as a flake-only repo.

## Usage

Run Plank directly:

```bash
nix run github:0xferrous/plankevm-flake#plank -- --help
```

Build the compiler package:

```bash
nix build github:0xferrous/plankevm-flake#plank
```

Build the tree-sitter grammar package:

```bash
nix build github:0xferrous/plankevm-flake#tree-sitter-plank
```


## Outputs

- `packages.<system>.plank`: Plank compiler CLI
- `packages.<system>.tree-sitter-plank`: Plank tree-sitter grammar
- `packages.<system>.default`: Alias for `plank`
- `apps.<system>.plank`: App wrapper for the Plank CLI
- `apps.<system>.default`: Alias for `plank`

The `plank` package includes the compiler, standard library, and local docs. The wrapped binary sets `PLANK_DIR` to the package output so `plank build` can find `stdlib/` and `plank doc` can find `share/doc/`.

## Branches and update workflows

This repo has two kinds of flake branches.

### `main` tracks upstream nightly/latest

The `main` branch is the rolling/nightly branch. Its `flake.lock` tracks the latest upstream `plankevm/plank-monorepo` default branch revision.

Use it when you want the newest Plank build:

```bash
nix run github:0xferrous/plankevm-flake/main#plank -- --help
```

The `Update flake lock` workflow runs daily at 06:00 UTC and can also be run manually. It:

1. checks out `main`
2. runs `nix flake update plank-monorepo`
3. verifies the updated flake with `nix flake check`, `nix build .#plank`, and `nix build .#tree-sitter-plank`
4. commits and pushes the updated `flake.lock` to `main` only if verification succeeds

### `tag/<upstream-tag>` branches track upstream release tags

Each upstream `plankevm/plank-monorepo` tag gets a matching branch in this repo:

```text
tag/<upstream-tag>
```

For example, upstream tag `v0.1.0` maps to this repo branch:

```text
tag/v0.1.0
```

Use a tag branch when you want a stable release build:

```bash
nix run github:0xferrous/plankevm-flake/tag/v0.1.0#plank -- --help
```

The `Sync upstream tag branches` workflow runs daily at 06:00 UTC and can also be run manually. It:

1. lists tags from `plankevm/plank-monorepo`
2. skips tags in the workflow skip list
3. skips tags that already have a `tag/<upstream-tag>` branch
4. dispatches `Sync one upstream tag branch` once for each missing tag branch

The `Sync one upstream tag branch` workflow takes a `tag` input. For that tag, it:

1. creates `tag/<tag>` from current `main` if the branch does not exist
2. reuses the existing `tag/<tag>` branch if it already exists
3. locks `plank-monorepo` to `github:plankevm/plank-monorepo/<tag>`
4. verifies the flake with `nix flake check`, `nix build .#plank`, and `nix build .#tree-sitter-plank`
5. commits and pushes only if verification succeeds

Existing tag branches are not recreated from `main` by the dispatcher. This avoids breaking older release branches if future `main` flake code changes in ways that are not compatible with old upstream tags.

Currently skipped upstream tags:

- `v0.0.1-alpha.1`
- `v0.0.1-alpha.2`

## Upstream

Source code lives in the upstream monorepo:

<https://github.com/plankevm/plank-monorepo>
