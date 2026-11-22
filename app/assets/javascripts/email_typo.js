// "Did you mean …?" under an email field, for a mistyped common domain (gmial.com,
// yahoo.con). It only suggests: the address as typed still goes through. The iOS app has the
// same list and rules (EmailTypo.swift).
(function() {
  window.DABBLE = window.DABBLE || {};

  var DOMAINS = [
    "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "hotmail.com", "outlook.com",
    "live.com", "msn.com", "icloud.com", "me.com", "mac.com", "aol.com", "comcast.net",
    "att.net", "sbcglobal.net", "verizon.net", "protonmail.com", "proton.me", "fastmail.com",
    "hey.com", "yahoo.co.uk", "hotmail.co.uk", "btinternet.com", "gmx.com", "gmx.de",
    "web.de", "mail.com", "zoho.com"
  ];
  var TLD_FIXES = { con: "com", cmo: "com", ocm: "com", vom: "com", xom: "com", comm: "com",
                    om: "com", cm: "com", nte: "net", ner: "net", nett: "net", orgg: "org", ogr: "org" };

  // Optimal string alignment distance: insertions, deletions, substitutions and swaps of
  // neighbouring letters each count one.
  function distance(a, b) {
    var d = [];
    for (var i = 0; i <= a.length; i++) { d[i] = [i]; }
    for (var j = 0; j <= b.length; j++) { d[0][j] = j; }
    for (i = 1; i <= a.length; i++) {
      for (j = 1; j <= b.length; j++) {
        var cost = a[i - 1] === b[j - 1] ? 0 : 1;
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
          d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
      }
    }
    return d[a.length][b.length];
  }

  // The address with its domain fixed, or null when it looks right (or isn't close to anything).
  function suggest(email) {
    email = (email || "").trim().toLowerCase();
    var at = email.lastIndexOf("@");
    if (at < 1 || at === email.length - 1) { return null; }
    var local = email.slice(0, at);
    var domain = email.slice(at + 1);
    if (DOMAINS.indexOf(domain) !== -1) { return null; }

    var best = null, bestDistance = 3;
    DOMAINS.forEach(function(candidate) {
      var d = distance(domain, candidate);
      if (d < bestDistance) { best = candidate; bestDistance = d; }
    });
    if (best && (bestDistance === 1 || (bestDistance === 2 && domain.length >= 6))) {
      return local + "@" + best;
    }

    var dot = domain.lastIndexOf(".");
    var fix = dot > 0 && TLD_FIXES[domain.slice(dot + 1)];
    if (fix) { return local + "@" + domain.slice(0, dot + 1) + fix; }
    return null;
  }

  // Shows the suggestion in hint (an element under the field) as a button that takes it.
  function watch(field, hint) {
    if (!field || !hint) { return; }
    var update = function() {
      var fixed = suggest(field.value);
      hint.textContent = "";
      hint.hidden = !fixed;
      if (!fixed) { return; }
      hint.appendChild(document.createTextNode("Did you mean "));
      var button = document.createElement("button");
      button.type = "button";
      button.className = "text-accent underline hover:text-primary font-medium";
      button.textContent = fixed;
      button.addEventListener("click", function() {
        field.value = fixed;
        hint.hidden = true;
        field.focus();
      });
      hint.appendChild(button);
      hint.appendChild(document.createTextNode("?"));
    };
    field.addEventListener("blur", update);
    field.addEventListener("input", function() { if (!hint.hidden) { update(); } });
    if (field.value) { update(); }
  }

  window.DABBLE.emailTypo = { suggest: suggest, watch: watch };
}());
