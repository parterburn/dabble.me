(function(){
  // The passkey page after sign-in (Passkeys::OffersController#show).
  window.DABBLE.pages.Passkeys_Offers_show = function(){
    var page = document.getElementById("passkey-offer");
    if (!page) { return; }
    var continueTo = page.getAttribute("data-continue-to") || "/";

    // Nothing to offer where the browser can't make a passkey.
    if (!DABBLE.webauthn.supported()) {
      window.location.replace(continueTo);
      return;
    }

    // Signed in a while ago: the button is a link to Account Security.
    if (page.getAttribute("data-proof-needed") === "true") { return; }

    var button = document.getElementById("add-passkey-offer");
    var error = document.getElementById("passkey-offer-error");

    button.addEventListener("click", function() {
      button.disabled = true;
      error.classList.add("hidden");
      DABBLE.webauthn.create(page.getAttribute("data-nickname") || "Passkey")
        .then(function(created) {
          if (!created) { button.disabled = false; return; }
          document.getElementById("passkey-offer-ask").classList.add("hidden");
          document.getElementById("passkey-offer-done").classList.remove("hidden");
          setTimeout(function() { window.location.assign(continueTo); }, 2500);
        })
        .catch(function(err) {
          button.disabled = false;
          error.textContent = (err && err.errors && err.errors[0]) ||
            "That didn't work. Try again, or add one later in Account Security.";
          error.classList.remove("hidden");
        });
    });
  };
})();
