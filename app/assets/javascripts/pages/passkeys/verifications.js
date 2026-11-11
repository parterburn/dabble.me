(function(){
  // The admin passkey check (Passkeys::VerificationsController#new).
  window.DABBLE.pages.Passkeys_Verifications_new = function(){
    var button = document.getElementById("verify-passkey");
    var error = document.getElementById("verify-passkey-error");
    if (!button) { return; }

    function showError(message) {
      error.textContent = message;
      error.classList.remove("hidden");
    }

    if (!DABBLE.webauthn.supported()) {
      button.disabled = true;
      showError("This browser can't use passkeys. Open Dabble Me in a browser that has your passkey.");
      return;
    }

    button.addEventListener("click", function() {
      button.disabled = true;
      error.classList.add("hidden");
      DABBLE.webauthn.verify()
        .then(function(done) { if (!done) { button.disabled = false; } })
        .catch(function(err) {
          button.disabled = false;
          showError((err && err.errors && err.errors[0]) || "That passkey couldn't be confirmed. Try again.");
        });
    });
  };
})();
