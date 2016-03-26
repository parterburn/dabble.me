(function(){
  window.DABBLE.pages.Entries_new = window.DABBLE.pages.Entries_create = function(){

    $(".j-image-remove").click(function( event ) {
      $("#entry_filepicker_url").val("");
      $(".j-image-preview").slideUp();
    });

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
      $(".navbar-brand i.fa-spinner").addClass("fa-spin");
    });

  };

}());