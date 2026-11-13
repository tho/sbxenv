DOCKERFILES := $(shell git ls-files '*.dockerfile' '*Dockerfile')

.PHONY: lint hadolint envfiles stale-kits

lint: hadolint envfiles

hadolint:
	hadolint $(DOCKERFILES)

# The env files differ only in header comments and in how they name the local
# kits. The remote one pins each local kit to a full commit SHA.
envfiles:
	@! grep -o '#ref=[^&]*' sbxenv.remote.yaml | grep -Ev '^#ref=[0-9a-f]{40}$$' || \
		{ echo 'sbxenv.remote.yaml: ref= must be a full commit SHA'; exit 1; }
	@# Compared in the shell, with no temp file or diff on stdin, so the check
	@# also runs in sandboxes that block those. diff only shows the drift.
	@remote=$$(sed 's|git+https://github.com/tho/sbxenv.git#ref=[0-9a-f]*&dir=|/path/to/sbxenv/|' sbxenv.remote.yaml); \
	[ "$$(grep -v '^#' sbxenv.example.yaml)" = "$$(printf '%s\n' "$$remote" | grep -v '^#')" ] || { \
		printf '%s\n' "$$remote" | diff -u -I '^#' sbxenv.example.yaml - 2>/dev/null; \
		echo 'sbxenv.remote.yaml: out of sync with sbxenv.example.yaml'; exit 1; }

# Fails if a local kit changed in HEAD since its ref= in sbxenv.remote.yaml.
# Not in lint: the ref= can only move in the commit after the kit change.
stale-kits:
	@stale=$$(sed -n 's|.*#ref=\([0-9a-f]*\)&dir=\(kits/[a-z]*\)$$|\1 \2|p' sbxenv.remote.yaml | \
		while read -r ref dir; do git diff --quiet "$$ref" HEAD -- "$$dir" || echo "$$dir"; done); \
	[ -z "$$stale" ] || { printf 'sbxenv.remote.yaml: ref= behind HEAD for:\n%s\n' "$$stale"; exit 1; }
