(function(){
  window.DABBLE.pages.Application_admin = function(){

    $(".j-admin-days").click(function(e) {
      e.preventDefault();
      $(this).parent().parent().parent().find(".j-admin-emails").slideToggle();
    });

    $(".j-admin-toggle-all").click(function(e) {
      e.preventDefault();
      $(".j-admin-emails").slideToggle();
      $(this).find('i').toggleClass("fa-minus")
    });

  };

}());