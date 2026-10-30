SHELL_SCRIPTS := $(shell git ls-files '*.sh')
DOCKERFILES := $(shell git ls-files '*.dockerfile' '*Dockerfile')

.PHONY: lint shellcheck hadolint envfiles

lint: shellcheck hadolint envfiles

shellcheck:
	shellcheck $(SHELL_SCRIPTS)

hadolint:
	hadolint $(DOCKERFILES)

# The two env files differ only in their header comments and in how they
# name the local kits, and every ref= in the remote one names one release.
envfiles:
	@refs=$$(sed -n 's/.*\.git#\(ref=[^&]*\)&.*/\1/p' sbxenv.remote.yaml | sort -u); \
	[ -n "$$refs" ] && [ "$$(printf '%s\n' "$$refs" | wc -l)" -eq 1 ] || \
		{ printf 'sbxenv.remote.yaml: refs differ:\n%s\n' "$$refs"; exit 1; }; \
	sed "s|/path/to/sbxenv/kits/\([a-z]*\)|git+https://github.com/tho/sbxenv.git#$$refs\&dir=kits/\1|" sbxenv.example.yaml | \
		diff -u -I '^#' - sbxenv.remote.yaml || \
		{ echo 'sbxenv.remote.yaml: out of sync with sbxenv.example.yaml'; exit 1; }
