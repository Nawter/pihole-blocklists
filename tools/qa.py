#!/usr/bin/env python3
"""QA suite. Exits non-zero on any failure -- run before every commit and deploy.

The point of this file is one thing: never block ourselves.

  python3 tools/qa.py         run all checks
  pytest tools/qa.py          same checks as pytest cases
"""
import re
import subprocess
import sys

import lists as L

RESULTS = []


def check(name):
    """Register a check. The function returns None/'' to pass, or a failure detail."""
    def deco(fn):
        RESULTS.append((name, fn))
        return fn
    return deco


def all_blocked():
    return sorted(set(sum((L.read(f) for f in L.ALL_LISTS), [])))


def allowed():
    return sorted(set(L.read("allowlist.txt")))


def regex_patterns():
    return L.read("regex.txt")


# --- 1. format ---------------------------------------------------------------

@check("all entries are bare lowercase domains")
def _fmt():
    bad = [d for d in all_blocked() if not L.DOMAIN_RE.match(d)]
    return f"malformed: {bad}" if bad else None


@check("no schemes, paths, ports or wildcards")
def _url():
    bad = [d for d in all_blocked() if re.search(r"://|/|:\d|^\*|\s", d)]
    return f"URL syntax: {bad}" if bad else None


@check("no raw IPs in domain lists")
def _ips():
    bad = [d for d in all_blocked() if re.fullmatch(r"(\d{1,3}\.){3}\d{1,3}", d)]
    return f"DNS cannot block IPs: {bad}" if bad else None


# --- 2. hygiene --------------------------------------------------------------

@check("no duplicates within any list")
def _dupes():
    out = []
    for f in L.ALL_LISTS:
        seen, dup = set(), set()
        for d in L.read(f):
            (dup if d in seen else seen).add(d)
        if dup:
            out.append(f"{f}: {sorted(dup)}")
    return "; ".join(out) or None


@check("every list is sorted")
def _sorted():
    bad = [f for f in L.ALL_LISTS if L.read(f) != sorted(L.read(f))]
    return f"not sorted (run 'make build' -- it sorts the source lists in place): {bad}" if bad else None


@check("no domain appears in two core lists")
def _cross():
    seen, dup = set(), set()
    for f in L.CORE_LISTS:
        for d in L.read(f):
            (dup if d in seen else seen).add(d)
    return f"in multiple lists: {sorted(dup)}" if dup else None


# --- 3. public suffix --------------------------------------------------------

@check("no bare TLD or public suffix blocked")
def _suffix():
    hit = sorted(set(all_blocked()) & L.PUBLIC_SUFFIXES)
    return f"WOULD BREAK THE INTERNET: {hit}" if hit else None


# --- 4. allowlist integrity --------------------------------------------------

@check("no domain both blocked and allowed")
def _conflict():
    hit = sorted(set(all_blocked()) & set(allowed()))
    return f"blocked and allowed: {hit}" if hit else None


@check("no regex pattern matches an allowlisted domain")
def _regex_vs_allow():
    allow = allowed()
    out = []
    for pat in regex_patterns():
        try:
            rx = re.compile(pat)
        except re.error:
            continue  # reported by the compile check
        hit = [d for d in allow if rx.search(d)]
        if hit:
            out.append(f"{pat} -> {hit}")
    return "; ".join(out) or None


# --- 5. critical smoke test --------------------------------------------------

@check("no critical host is blocked, by exact entry or regex")
def _critical():
    blocked = set(all_blocked())
    out = []
    for d in L.CRITICAL:
        if d in blocked:
            out.append(f"{d} (exact)")
        for pat in regex_patterns():
            try:
                if re.search(pat, d):
                    out.append(f"{d} (regex {pat})")
            except re.error:
                pass
    return "; ".join(out) or None


# --- 6. regex validity -------------------------------------------------------

@check("all regex patterns compile")
def _compile():
    bad = []
    for pat in regex_patterns():
        try:
            re.compile(pat)
        except re.error as e:
            bad.append(f"{pat} ({e})")
    return "; ".join(bad) or None


@check(r"every pattern is anchored (\.|^)...$")
def _anchored():
    bad = [p for p in regex_patterns()
           if not (p.startswith(r"(\.|^)") and p.endswith("$"))]
    return f"unanchored (over-blocks): {bad}" if bad else None


@check("patterns match self and subdomains, reject lookalikes")
def _semantics():
    bad = []
    for d in all_blocked():
        pat = L.regex_for(d)
        if pat not in regex_patterns():
            continue
        rx = re.compile(pat)
        if not rx.search(d):
            bad.append(f"{d} (misses itself)")
        if not rx.search("a." + d):
            bad.append(f"{d} (misses subdomain)")
        if rx.search("evil" + d):
            bad.append(f"{d} (leaks onto evil{d})")
    return "; ".join(bad) or None


# --- 7. expanded lists -------------------------------------------------------

@check("expanded lists contain every base domain")
def _exp_covers():
    out = []
    for f in L.ALL_LISTS:
        missing = set(L.read(f)) - set(L.read(L.expanded_name(f)))
        if missing:
            out.append(f"{f}: {sorted(missing)[:5]}")
    return "; ".join(out) or None


@check("no allowlisted or critical host in any expanded list")
def _exp_safe():
    bad = set()
    guard = set(allowed()) | set(L.CRITICAL)
    for f in L.ALL_LISTS:
        bad |= set(L.read(L.expanded_name(f))) & guard
    return f"expanded list blocks: {sorted(bad)}" if bad else None


@check("expanded lists are well formed")
def _exp_fmt():
    bad = []
    for f in L.ALL_LISTS:
        bad += [d for d in L.read(L.expanded_name(f)) if not L.DOMAIN_RE.match(d)]
    return f"malformed: {bad[:5]}" if bad else None


# --- 8. build freshness ------------------------------------------------------

@check("derived files are up to date with the source lists")
def _fresh():
    r = subprocess.run([sys.executable, L.path("tools/build.py"), "--check"],
                       capture_output=True, text=True, cwd=L.path("tools"))
    return r.stdout.strip() if r.returncode else None


def main():
    passed = failed = 0
    for name, fn in RESULTS:
        detail = fn()
        if detail:
            print(f"  \033[31mFAIL\033[0m {name}\n       {detail}")
            failed += 1
        else:
            print(f"  \033[32mPASS\033[0m {name}")
            passed += 1
    print(f"\n\033[1m{passed} passed, {failed} failed\033[0m")
    if failed:
        print("QA FAILED -- do not deploy")
        sys.exit(1)
    print("QA clean -- safe to commit and deploy")


# pytest discovers these automatically: one test per check.
def pytest_generate_tests(metafunc):
    if "qa_case" in metafunc.fixturenames:
        metafunc.parametrize("qa_case", RESULTS, ids=[n for n, _ in RESULTS])


def test_qa(qa_case):
    name, fn = qa_case
    detail = fn()
    assert not detail, f"{name}: {detail}"


if __name__ == "__main__":
    main()
