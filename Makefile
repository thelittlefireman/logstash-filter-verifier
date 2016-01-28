# Copyright (c) 2015-2016 Magnus Bäck <magnus@noun.se>

# An empty GOPATH can result in slightly confusing error messages.
ifeq ($(GOPATH),)
$(error The GOPATH environment variable needs to be set)
endif

# Installation root directory. Should be left alone except for
# e.g. package installations. If you want to control the installation
# directory for normal use you should modify PREFIX instead.
DESTDIR :=

ifeq ($(OS),Windows_NT)
EXEC_SUFFIX := .exe
else
EXEC_SUFFIX :=
endif

# The Docker image to use when building release images.
GOLANG_DOCKER_IMAGE := golang:1.5.3

# Installation prefix directory. Could be changed to e.g. /usr or
# /opt/logstash-filter-verifier.
PREFIX := /usr/local

# The name of the executable produced by this makefile.
PROGRAM := logstash-filter-verifier

# List of all GOOS_GOARCH combinations that we should build release
# binaries for. See https://golang.org/doc/install/source#environment
# for all available combinations.
TARGETS := darwin_amd64 linux_386 linux_amd64 windows_386 windows_amd64

VERSION := $(shell git describe --tags --always)

GOCOV      := $(GOPATH)/bin/gocov$(EXEC_SUFFIX)
GOCOV_HTML := $(GOPATH)/bin/gocov-html$(EXEC_SUFFIX)
OVERALLS   := $(GOPATH)/bin/overalls$(EXEC_SUFFIX)

.PHONY: all
all: $(PROGRAM)$(EXEC_SUFFIX)

# Depend on this target to force a rebuild every time.
.FORCE:

# Generate version.go based on the "git describe" output so that
# the reported version number is always descriptive and useful.
# This rule must always run but the target file is only updated if
# there's an actual change in the version number.
.PRECIOUS: version.go
version.go: .FORCE
	TMPFILE=$$(mktemp $@.XXXX) && \
	    echo "package main" >> $$TMPFILE && \
	    echo "const VERSION = \"$(VERSION)\"" >> $$TMPFILE && \
	    gofmt -w $$TMPFILE && \
	    if ! cmp --quiet $$TMPFILE $@ ; then \
	        mv $$TMPFILE $@ ; \
	    fi && \
	    rm -f $$TMPFILE

$(GOCOV):
	go get github.com/axw/gocov/gocov

$(GOCOV_HTML):
	go get gopkg.in/matm/v1/gocov-html

$(OVERALLS):
	go get github.com/go-playground/overalls

# The Go compiler is fast and pretty good about figuring out what to
# build so we don't try to to outsmart it.
$(PROGRAM)$(EXEC_SUFFIX): .FORCE version.go
	go get -d
	go build -o $@

.PHONY: clean
clean:
	rm -f $(PROGRAM)$(EXEC_SUFFIX)
	rm -rf dist

# To be able to build a Debian package from any commit and get a
# meaningful result, use "git describe" to find the current version
# number and compare it to the most recent entry in debian/changelog
# (which is what Debian build system uses when creating a package).
# If those versions are different, write a new entry with the current
# version.
#
# Replace hyphens with plus signs to comply with Debian policy and
# transform '-rcX' to '~rcX' so that a release candidate is considered
# older than the final release.
.PHONY: deb
deb:
	CURRENT_VERSION=$$(sed -n '1s/^[^ ]* (\([^)]*\)).*/\1/p' \
	        < debian/changelog) && \
	    ACTUAL_VERSION=$$(echo "$(VERSION)" | \
	            sed 's/-rc/~rc/; s/-/+/g') && \
	    if [ "$$CURRENT_VERSION" != "$$ACTUAL_VERSION" ] ; then \
	        dch --force-bad-version --newversion $$ACTUAL_VERSION \
	                "Autogenerated changelog entry" ; \
	    fi
	debuild --preserve-envvar GOPATH -uc -us

.PHONY: install
install: $(PROGRAM)$(EXEC_SUFFIX)
	mkdir -p $(DESTDIR)$(PREFIX)/bin
	install -m 0755 --strip $(PROGRAM)$(EXEC_SUFFIX) $(DESTDIR)$(PREFIX)/bin

.PHONY: release-tarballs
release-tarballs: dist/$(PROGRAM)_$(VERSION).tar.gz \
    $(addsuffix .tar.gz,$(addprefix dist/$(PROGRAM)_$(VERSION)_,$(TARGETS)))

dist/$(PROGRAM)_$(VERSION).tar.gz:
	mkdir -p $(dir $@)
	git archive --output=$@ HEAD

dist/$(PROGRAM)_$(VERSION)_%.tar.gz: version.go
	mkdir -p $(dir $@)
	GOOS="$$(basename $@ .tar.gz | awk -F_ '{print $$3}')" && \
	    GOARCH="$$(basename $@ .tar.gz | awk -F_ '{print $$4}')" && \
	    DISTDIR=dist/$${GOOS}_$${GOARCH} && \
	    if [ $$GOOS = "windows" ] ; then EXEC_SUFFIX=".exe" ; fi && \
	    mkdir -p $$DISTDIR && \
	    cp README.md LICENSE $$DISTDIR && \
	    docker run -it --rm -v $$GOPATH:$$GOPATH -w $$(pwd) \
	        -e GOPATH=$$GOPATH -e GOOS=$$GOOS -e GOARCH=$$GOARCH \
	        $(GOLANG_DOCKER_IMAGE) \
	        go build -o $$DISTDIR/$(PROGRAM)$$EXEC_SUFFIX && \
	    tar -C $$DISTDIR -zcpf $@ . && \
	    rm -rf $$DISTDIR

.PHONY: test
test: $(GOCOV) $(GOCOV_HTML) $(OVERALLS) $(PROGRAM)$(EXEC_SUFFIX)
	$(OVERALLS) -project=$$(go list .) -covermode=count -debug
	$(GOCOV) convert overalls.coverprofile | $(GOCOV_HTML) > coverage.html
