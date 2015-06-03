(function(){
  window.DABBLE.pages.Import_show = function(){

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
      $(".navbar-brand i.fa-spinner").addClass("fa-spin");
    });

  };

}());