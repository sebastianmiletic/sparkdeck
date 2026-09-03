# Sparkdeck configuration for Kupfer

This repository contains the laptop Hyprland/Quickshell setup. It can be installed on Kupfer Linux, but hardware-specific settings must be reviewed: the target phone is OnePlus 6 (`enchilada`), not OnePlus 6T (`fajita`). Keep Phosh and Squeekboard available as the touchscreen fallback.

## Packages

Install the ARM64 packages required by the configs using the target's package manager: `hyprland`, `hyprlock`, `quickshell`, `waybar`, `wofi`, `foot`, `mako`, `thunar`, `pipewire`, `wireplumber`, `xdg-desktop-portal-hyprland`, `jq`, `brightnessctl`, `grim`, `slurp`, `wl-clipboard`, and `cliphist` where available.

## Install user files

Copy `hypr/`, `quickshell/`, and `foot/` into `~/.config/`, and copy `systemd/user/quickshell.service` into `~/.config/systemd/user/`. Then run `systemctl --user daemon-reload` and `systemctl --user enable --now quickshell.service` from inside Hyprland.

Review monitor and input settings before starting Hyprland. Use `DSI-1` for the phone display and retain Phosh as fallback. Do not run arbitrary scripts as root. Keep secrets and API keys outside this repository.
