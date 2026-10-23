# Hooks wiring (linked to ~/.config/git/hooks.inc). Skip with `bootstrap.sh --no-hooks`.
# Which checks run is decided by dotfiles.profile / hooks.* in your overlay
# (see docs/GIT-CONFIG.md). Needs the default XDG location (~/.config/git).
[core]
	hooksPath = ~/.config/git/hooks
