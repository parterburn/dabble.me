(function(){
  window.DABBLE.pages.Registrations_edit = function(){
    $(".j-delete-user").on({
      click: function(e){
        if ($('#user_current_password').val().length === 0) {
          swal({title: "Password Needed", text: "Enter your current password to delete your account.", type: "warning", confirmButtonText: "Ok"});
          return false;
        }
      }
    });
  };
}());