"""Course mode's two sides of an address (Frank, 1 Nov 2026: "die komischen adressen sollten eigentlich nicht in die
KI gehen ... idealerweise werden die email addressen immer ins realistische und zurück konvertiert").

The provider carries the transport side: the own address and its plus addresses. n8n and Langflow see the case side:
the case's person and correspondents under their real addresses. The case files keep ".example" (kingo-pod is
public, and nothing there can reach anyone); the export takes it off, since the model sorts a mail with .example
addresses differently (Frank, 1 Nov: "ja, richtige addressen"; one test mail: calendar in 6 of 20 runs with .example,
20 of 20 without).

  in   the own address becomes the case's person (case.json "address", shown without ".example"), in the
       headers, the subject and the text; every case address loses ".example" (the domain school.edu.example
       becomes school.edu, enron.example becomes enron.com again). A mail this
       service sent carries X-Kingo-Sent, and its case addresses in X-Kingo-To and X-Kingo-Cc, which are taken
       instead of To and Cc; only such a mail gets the tag own.
  out  the case's person becomes the own address; a case contact (an address in the case files) becomes a plus
       address of the own one, so the mail lands in the own inbox and nowhere else (Frank, 2 Nov: only the case's
       contacts, "a"); any other address stays, and course mode refuses it unless `kingo mail` allowed it. The
       addresses as written travel along in X-Kingo-To and X-Kingo-Cc.

With course mode off, nothing happens. With a case address course mode cannot be off (case.py): the database then
holds real addresses.
"""

import re
from email.headerregistry import Address
from email.utils import getaddresses

SENT_HEADER, TO_HEADER, CC_HEADER = "X-Kingo-Sent", "X-Kingo-To", "X-Kingo-Cc"
LOCAL_CHARS = "A-Za-z0-9._%+'-"
# Starts only where a local part starts, so a long run of such characters costs one pass, not one per position;
# ends where the domain ends: ".example." at the end of a sentence counts, "x.example.com" does not.
EXAMPLE_ADDRESS = re.compile(rf"(?<![{LOCAL_CHARS}])[{LOCAL_CHARS}]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.example"
                             r"(?![\w-]|\.[\w-])", re.I)


def real(addr):
    """Takes ".example" off the domain: school.edu.example -> school.edu, enron.example -> enron.com (the case build
    made every Enron domain enron.example). A domain without a dot left (an invented one, quantsearch.example) and
    any other address stay."""
    if not addr or not addr.lower().endswith(".example"):
        return addr
    local, _, domain = addr[:-len(".example")].rpartition("@")
    if domain.lower() == "enron" or domain.lower().endswith(".enron"):
        domain += ".com"
    elif "." not in domain:
        return addr
    return f"{local}@{domain}"


def format_entry(name, addr):
    """Like notmuch.address_list: 'Name <a@x>' with the name as it is (no encoded words), quoted where needed."""
    if not name:
        return addr
    try:
        return str(Address(display_name=name, addr_spec=addr))
    except Exception:
        return f"{name} <{addr}>"


class Persona:
    def __init__(self, own, case=None, allowed=(), contacts=()):
        self.own = own.strip().lower()
        self.local, _, self.domain = self.own.rpartition("@")
        self.case = real((case or "").strip().lower()) or None   # as n8n sees it
        self.case_files = (case or "").strip().lower() or None   # as the case files write it
        self.allowed = {a.strip().lower() for a in allowed if a.strip()}
        self.contacts = {real(a.strip().lower()) for a in contacts if a.strip()}   # the case's correspondents
        self._own_in_text = re.compile(r"(?<![\w.+-])" + re.escape(self.own) + r"(?![\w-])", re.I)

    def mine(self, addr):
        """The own address or one of its plus addresses."""
        local, _, domain = (addr or "").lower().rpartition("@")
        return domain == self.domain and local.split("+", 1)[0] == self.local

    # -- in: what the provider carries -> what n8n and Langflow see ------------------------------------------

    def case_addr(self, addr):
        if not self.case or not addr:
            return addr
        return self.case if addr.lower() == self.own else real(addr)

    def case_text(self, text):
        if not self.case or not text:
            return text
        return EXAMPLE_ADDRESS.sub(lambda m: real(m.group(0)), self._own_in_text.sub(self.case, text))

    def case_entries(self, entries):
        """['Name <a@x>', 'b@y'] with the own address as the case's person, names kept; an entry whose address
        stays is kept as it came."""
        out = []
        for e in entries or []:
            parsed = [(n, a) for n, a in getaddresses([e]) if a]
            if len(parsed) == 1 and self.case_addr(parsed[0][1]) != parsed[0][1]:
                out.append(format_entry(parsed[0][0], self.case_addr(parsed[0][1])))
            else:
                out.append(e)
        return out

    # -- out: what n8n wrote -> what the provider may carry --------------------------------------------------

    def case_contact(self, addr):
        a = (addr or "").strip().lower()
        return a.endswith(".example") or a in self.contacts

    def transport_addr(self, addr):
        a = (addr or "").strip().lower()
        if self.case and a in (self.case, self.case_files):
            return self.own
        if a in self.allowed or self.mine(a) or not self.case_contact(a):
            return addr   # allowed, or refused by course mode (outbox.not_allowed)
        room = max(1, 63 - len(self.local))   # a local part has at most 64 octets (RFC 5321)
        tag = re.sub(r"[^a-z0-9]+", "-", a.rpartition("@")[0]).strip("-")[:min(40, room)].strip("-") or "case"
        return f"{self.local}+{tag}@{self.domain}"

    def transport(self, entries):
        """['Name <a@x>', 'b@y'] with addresses the provider may carry, names kept."""
        out = []
        for e in entries or []:
            (n, a), = [(n, a) for n, a in getaddresses([e]) if a]   # outbox.build checked: one address each
            out.append(format_entry(n, self.transport_addr(a)) if self.transport_addr(a) != a else e)
        return out
