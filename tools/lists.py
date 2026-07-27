"""Shared list handling for build.py and qa.py.

Single source of truth for: where the files are, what counts as a domain,
and which host prefixes the expanded lists use.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Hand-edited sources. proxy-listicles is opt-in: expanded, but no regex shipped.
CORE_LISTS = ["temp-email-sites.txt", "free-proxy-sites.txt", "adult-chat-sites.txt"]
OPTIN_LISTS = ["proxy-listicles-sites.txt"]
ALL_LISTS = CORE_LISTS + OPTIN_LISTS

# Host prefixes proxy/temp-mail/chat sites actually use. Only relevant to
# expanded/; regex.txt covers every subdomain without needing to guess.
PREFIXES = """www m mobile app apps chat chats live video videos stream en us uk
es fr de ru pl it tr pt ar nl api cdn static media web my free go beta secure
login account new play room random talk meet date girls vip pro premium mail
smtp""".split()

DOMAIN_RE = re.compile(r"^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$")

# Blocking any of these takes out every site beneath it. Never allowed in a list.
PUBLIC_SUFFIXES = set("""com net org io co dev app xyz uk de fr nl ru pl it es br
in cn jp au ca us me tv cc ai so la lol biz info site online shop chat email
co.uk com.au co.nz co.za com.br co.jp org.uk ac.uk gov.uk com.tr com.mx co.kr
com.cn edu.vn com.vn edu.ge""".split())

# Hardcoded on purpose: if someone deletes a line from allowlist.txt, the QA
# smoke test must still catch the breakage.
CRITICAL = """api.anthropic.com claude.ai console.anthropic.com github.com
raw.githubusercontent.com codeload.github.com registry.npmjs.org pypi.org
files.pythonhosted.org apple.com swcdn.apple.com icloud.com
login.microsoftonline.com outlook.com office.com google.com googleapis.com
gstatic.com zoom.us slack.com cloudflare.com mozilla.org paloaltonetworks.com
registry-1.docker.io""".split()


def path(*parts):
    return os.path.join(ROOT, *parts)


def read(rel):
    """Domains from a list file: lowercased, comments and blanks dropped."""
    p = rel if os.path.isabs(rel) else path(rel)
    if not os.path.exists(p):
        return []
    out = []
    for line in open(p):
        s = line.split("#")[0].strip().lower()
        if s:
            out.append(s)
    return out


def regex_for(domain):
    """Pi-hole wildcard pattern: matches the domain and every subdomain."""
    return r"(\.|^)" + domain.replace(".", r"\.") + "$"


def expanded_name(list_file):
    return "expanded/" + list_file.replace(".txt", "-expanded.txt")


def is_registrable(domain):
    """True if `domain` is a name someone registered, not an existing subdomain.

    Only registrable names get prefix-expanded: `www.example.com` is useful,
    `www.mail.example.com` is noise. One dot is the common case, but two-label
    suffixes make `tempmail.co.uk` registrable with two dots -- miss that and
    every .co.uk entry silently loses its www variant.
    """
    parts = domain.split(".")
    if len(parts) == 2:
        return True
    if len(parts) == 3 and ".".join(parts[1:]) in PUBLIC_SUFFIXES:
        return True
    return False
