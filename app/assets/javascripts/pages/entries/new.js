(function(){
  window.DABBLE.pages.Entries_new = window.DABBLE.pages.Entries_create = function(){

    $(".j-image-remove").click(function( event ) {
      $(".j-image-preview").slideUp();
    });

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
      $(".navbar-brand i.fa-spinner").addClass("fa-spin");
    });

  };

}());