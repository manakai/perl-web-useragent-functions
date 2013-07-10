## Run tests:
##   $ make test
## Update dependency list:
##   $ make local-submodules pmb-update
## Install dependent modules into ./local/:
##   $ make pmb-install
## Generate tarballs:
##   $ make dist

all:

Makefile-setupenv: Makefile.setupenv
	$(MAKE) --makefile Makefile.setupenv setupenv-update \
            SETUPENV_MIN_REVISION=20120318

Makefile.setupenv:
	wget -O $@ https://raw.github.com/wakaba/perl-setupenv/master/Makefile.setupenv

lperl local-perl perl-version perl-exec \
pmb-update pmb-install \
local-submodules remotedev-test \
generatepm: %: Makefile-setupenv
	$(MAKE) --makefile Makefile.setupenv $@

PROVE = prove
PERL_VERSION = latest
PERL_PATH = $(abspath local/perlbrew/perls/perl-$(PERL_VERSION)/bin)

test: safetest

test-deps: git-submodules local-submodules pmb-install lperl

GIT = git

git-submodules:
	$(GIT) submodule update --init

safetest: test-deps
	PATH=$(PERL_PATH):$(PATH) PERL5LIB=$(shell cat config/perl/libs.txt) \
            $(PROVE) t/*.t

GENERATEPM = local/generatepm/bin/generate-pm-package
GENERATEPM_ = $(GENERATEPM) --generate-json

dist: generatepm
	mkdir -p dist
	$(GENERATEPM_) config/dist/lwp-useragent-curl.pi dist
	$(GENERATEPM_) config/dist/web-useragent-functions.pi dist

dist-wakaba-packages: local/wakaba-packages dist
	cp dist/*.json local/wakaba-packages/data/perl/
	cp dist/*.tar.gz local/wakaba-packages/perl/
	cd local/wakaba-packages && $(MAKE) all

local/wakaba-packages: always
	git clone "git@github.com:wakaba/packages.git" $@ || (cd $@ && git pull)
	cd $@ && git submodule update --init

always:
