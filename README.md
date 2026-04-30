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

Enter the development shell:

```bash
nix develop github:0xferrous/plankevm-flake
```

## Outputs

- `packages.<system>.plank`: Plank compiler CLI
- `packages.<system>.tree-sitter-plank`: Plank tree-sitter grammar
- `packages.<system>.default`: Alias for `plank`
- `apps.<system>.plank`: App wrapper for the Plank CLI
- `apps.<system>.default`: Alias for `plank`
- `devShells.<system>.default`: Rust/mdBook development shell

The `plank` package includes the compiler, standard library, and local docs. The wrapped binary sets `PLANK_DIR` to the package output so `plank build` can find `stdlib/` and `plank doc` can find `share/doc/`.

## Upstream

Source code lives in the upstream monorepo:

<https://github.com/plankevm/plank-monorepo>
