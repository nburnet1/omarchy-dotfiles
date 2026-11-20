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
In a running Hyprland session it also rescans Omarchy plugins and reloads the
shell layout so the custom 1–5 workspace buttons are discovered immediately.
The Bash and Neovim files are snapshots of the configuration at publication time;
run the installer to manage the live copies through this repository.

Separately cloned themes, application data, credentials, and shell history are
not included. The Zen theme hook currently uses the base stylesheet from
`~/Programs/dotfiles/.config/zen/userChrome.css` when available.

## Ignition Designer on Wayland / Kasm (optional)

After installing the vendor's Designer Launcher, launch it once and save a
Designer entry. Save your work and close both Designer and Designer Launcher,
then run:

```sh
python3 scripts/configure-ignition-designer.py --scale 1
python3 scripts/configure-ignition-designer.py --scale 1 --check
```

For multiple saved entries, also supply `--application 'ENTRY NAME'`. Omit
`--scale 1` on a native desktop where you want its normal display scaling.

This reapplies the settings verified with Ignition **8.3.10** in the
[Kasm/Selkies container](https://github.com/nburnet1/kasm-omarchy-quattro):

- A small XML file disables `Synthetica.popupRobot.enabled`. The vendor's
  `ignition.synthetica.customXml` setting (supported since 8.1.48) prevents menus
  from requesting screen-sharing permission for popup background captures.
- `-Dawt.useSystemAAFontSettings=on` and `-Dswing.aatext=true` enable Java text
  antialiasing for the selected Designer entry. They do not change the system
  font or other applications.
- The optional scale sets `GDK_SCALE` on the existing launcher and both URL/file
  handlers. This reaches both JavaFX Launcher and its Designer child, including
  when the running dock/terminal still has an older scale in its environment.

Reopen via the **Designer Launcher desktop entry**, rather than running the
vendor shell script from an old terminal. The vendor script itself is unchanged.
Rerun the command if a launcher update regenerates its desktop entries. After
changing Hyprland environment settings, a fresh desktop session also avoids
stale settings in already-running applications.

The command preserves unrelated settings, rejects conflicting custom XML/Java
overrides, and creates timestamped backups only when files change. Launcher JSON
and its backups can contain gateway details; they stay in your home directory,
outside this repository. No launcher binaries, runtime, project, or gateway data
are included. To undo, close both apps, remove the three added JVM arguments,
remove `env GDK_SCALE=1` from the three desktop Exec lines, and remove the copied
popup XML; use the backups if no later settings need preserving.

Vendor reference: [Synthetica popup screen-capture setting](https://forum.inductiveautomation.com/t/ignition-8-1-45-designer-asking-for-monitor-sharing/102767/8).
