.PHONY: help build qa check deploy hosts-on hosts-off pf-on pf-off refresh-ips refresh-upstream clean
.DEFAULT_GOAL := help

PY ?= python3

help:  ## show this help
	@grep -hE '^[a-z-]+:.*?##' $(MAKEFILE_LIST) | sed 's/:.*##/\t/' | expand -t22

build:  ## regenerate expanded/ and regex.txt from the source lists
	@$(PY) tools/build.py

qa:  ## run the QA suite (gates deploy; exits non-zero on failure)
	@$(PY) tools/qa.py

check:  ## diagnose: make check DOMAIN=foo.com, or make check DNS=192.168.1.5
	@bash scripts/check.sh $(or $(DOMAIN),$(DNS))

deploy:  ## push allowlist + regex to Pi-hole, rebuild gravity (run on the Pi)
	@sudo bash scripts/deploy.sh

hosts-on:  ## block domains on this Mac via /etc/hosts
	@sudo bash local-mac/macblock.sh hosts-on

hosts-off:  ## remove the /etc/hosts block
	@sudo bash local-mac/macblock.sh hosts-off

pf-on:  ## block proxy IPs on this Mac via pf
	@sudo bash local-mac/macblock.sh pf-on

pf-off:  ## remove the pf block
	@sudo bash local-mac/macblock.sh pf-off

status:  ## what is currently active on this Mac
	@bash local-mac/macblock.sh status

refresh-ips:  ## re-scrape firewall/proxy-ips.txt (FULL=1 for the ~43k version)
	@$(PY) local-mac/refresh-ips.py $(if $(FULL),--full,)

refresh-upstream:  ## fetch hagezi's list (~90k hostnames) for hosts-on (local-mac only)
	@$(PY) local-mac/refresh-upstream.py

clean:  ## remove Python caches (expanded/ and regex.txt are COMMITTED -- never deleted)
	@rm -rf tools/__pycache__
	@echo "removed caches. expanded/ and regex.txt back the published adlist URLs; edit sources and 'make build' instead"
