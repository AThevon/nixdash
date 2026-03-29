<p align="center">
  <img src="assets/nixdash.png" alt="nixdash" width="160" />
</p>

<h1 align="center">nixdash</h1>

<p align="center">TUI for managing Nix packages. Search, install, remove, and create temporary shells — all from one interactive interface.</p>

## Features

- **List** installed packages with type indicators (nixpkgs, flake, conditional)
- **Search** nixpkgs with real-time fuzzy search via nix-search-tv
- **Install/Remove** packages with diff preview and confirmation
- **Temporary shells** with multiselect package picker
- **External flake inputs** — guided setup for custom flake packages
- **Configurable** — works with Home Manager, NixOS, or any Nix setup

## Install

Add to your `flake.nix`:

```nix
inputs.nixdash.url = "github:AThevon/nixdash";
inputs.nixdash.inputs.nixpkgs.follows = "nixpkgs";
```

Then add to your packages:

```nix
nixdash.packages.${system}.default
```

Run `nixdash init` to configure.

## Usage

```bash
nixdash              # Interactive hub
nixdash list         # List installed packages
nixdash search       # Search & install
nixdash search curl  # Search with initial query
nixdash shell        # Temporary shell (multiselect)
nixdash shell curl   # Temporary shell with curl
nixdash add-flake    # Add external flake input
nixdash config       # Settings
nixdash init         # Setup wizard
```

## Dependencies

Injected automatically via Nix:
- [fzf](https://github.com/junegunn/fzf)
- [gum](https://github.com/charmbracelet/gum)
- [jq](https://github.com/jqlang/jq)
- [nix-search-tv](https://github.com/3timeslazy/nix-search-tv)

## License

MIT
