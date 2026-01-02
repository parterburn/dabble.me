(function(){
  window.DABBLE.pages.Devise_Registrations_new = window.DABBLE.pages.Registrations_new = function(){
    var rememberedEmail = DABBLE.webauthn.getCookie("dabble_passkey_user_hint");
    if (rememberedEmail) {
      // Don't auto-populate the email field, but use the hint to trigger the passkey prompt
      DABBLE.webauthn.authenticate(rememberedEmail);
    }

    $("#login-button").on("click", function(e) {
      e.preventDefault();
      var email = $("#login-email").val();
      if (!email) {
        $("#login-email").focus();
        return;
      }

      // Try passkey first
      $.ajax({
        url: "/passkeys/sessions/new",
        type: "GET",
        data: { email: email },
        dataType: "json",
        success: function(options) {
          if ((options.allowCredentials && options.allowCredentials.length > 0) || (options.allow_credentials && options.allow_credentials.length > 0)) {
            DABBLE.webauthn.authenticate(email);
          } else {
            // No passkeys, redirect to regular login
            window.location.href = "/users/sign_in?user[email]=" + encodeURIComponent(email);
          }
        },
        error: function() {
          // Error or user not found, redirect to regular login
          window.location.href = "/users/sign_in?user[email]=" + encodeURIComponent(email);
        }
      });
    });
  };
}());
