# Omarchy dotfiles

Personal Omarchy configuration managed with GNU Stow.

## Included

- `hypr`: Hyprland configuration
- `omarchy`: shell layout, custom workspace widget, and hooks
- `bash`: `.bashrc` (including `vim`, `vi`, and `v` aliases for Neovim)
- `nvim`: Neovim/LazyVim configuration and plugin lockfile

## Install

On an Omarchy installation with GNU Stow installed:

```sh
./install.sh
```

The installer backs up conflicting configuration before linking these packages.
The Bash and Neovim files are snapshots of the configuration at publication time;
run the installer to manage the live copies through this repository.

Separately cloned themes, application data, credentials, and shell history are
not included. The Zen theme hook currently uses the base stylesheet from
`~/Programs/dotfiles/.config/zen/userChrome.css` when available.
