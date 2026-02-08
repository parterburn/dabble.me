(function(){
  window.DABBLE.pages.Devise_Sessions_new = window.DABBLE.pages.Sessions_new = function(){
    var rememberedEmail = DABBLE.webauthn.getCookie("dabble_passkey_user_hint");
    if (rememberedEmail) {
      // Don't auto-populate the email field, but use the hint to trigger the passkey prompt
      DABBLE.webauthn.authenticate(rememberedEmail);
    }

    $("#login-passkey").on("click", function(e) {
      e.preventDefault();
      var email = $("#user_email").val() || rememberedEmail;
      if (!email) {
        alert("Please enter your email address first.");
        $("#user_email").focus();
        return;
      }
      DABBLE.webauthn.authenticate(email);
    });
  };
}());
