(function(){
  window.DABBLE.pages.Registrations_security = window.DABBLE.pages.Registrations_settings = window.DABBLE.pages.Registrations_edit = window.DABBLE.pages.Registrations_update = function(){

    $(".j-delete-user, .j-edit-security").on({
      click: function(e){
        if ($('#user_current_password').val().length === 0) {
          swal({title: "Password Needed", text: "Enter your current password.", type: "error", confirmButtonText: "Ok"});
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

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
    });

  };
}());
