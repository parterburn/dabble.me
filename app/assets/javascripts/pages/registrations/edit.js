(function(){
    window.DABBLE.pages.Registrations_delete_account = window.DABBLE.pages.Registrations_security = window.DABBLE.pages.Registrations_settings = window.DABBLE.pages.Registrations_edit = window.DABBLE.pages.Registrations_update = function(){

    // The password, or the emailed code on an account with no password.
    var $proof = $('#user_current_password').length ? $('#user_current_password') : $('#user_email_code');
    var proofNeeded = $('#user_current_password').length
      ? { title: "Password Needed", text: "Enter your current password." }
      : { title: "Code Needed", text: "Tap Email me a code, then enter the code from the email." };

    $(".j-delete-user, .j-edit-security").on({
      click: function(e){
        if ($proof.length > 0 && $proof.val().length === 0) {
          swal({title: proofNeeded.title, text: proofNeeded.text, type: "error", confirmButtonText: "Ok"});
          return false;
        }
      }
    });

    var tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    $.extend($.fn.pickadate.defaults, {
      format: 'mmmm d, yyyy',
      selectYears: true,
      selectMonths: true,
      max: tomorrow,
      selectYears: 20
    });

    $('.pickadate').pickadate();
    
    $("#add-passkey").on("click", function(e) {
      e.preventDefault();

      // Not needed just after signing in with an emailed code (data-proof-needed="false").
      if ($(this).data("proof-needed") !== false && $proof.length > 0 && $proof.val().length === 0) {
        swal({title: proofNeeded.title, text: proofNeeded.text + " Then tap Add Passkey.", type: "error", confirmButtonText: "Ok"});
        $proof.focus();
        return false;
      }

      var nickname = prompt("Enter a nickname for this passkey (e.g. MacBook Air, YubiKey):", "Passkey");
      if (nickname) {
        DABBLE.webauthn.register(nickname, $('#user_current_password').val(), $('#user_email_code').val());
      }
    });

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
    });

  };
}());
