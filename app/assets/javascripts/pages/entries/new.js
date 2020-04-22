(function(){
  window.DABBLE.pages.Entries_new = window.DABBLE.pages.Entries_create = function(){

    $(".j-image-remove").click(function( event ) {
      $(".j-image-preview").slideToggle();
    });

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
    });

    var tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    $.extend($.fn.pickadate.defaults, {
      format: 'mmmm d, yyyy',
      selectYears: true,
      selectMonths: true,
      max: tomorrow
    });

    $('.pickadate').pickadate();  

    Offline.on("down", function () {
        $("form input[type=submit]").attr("disabled", "disabled").addClass("disabled");
    });

    Offline.on("up", function () {
        $("form input[type=submit]").removeAttr("disabled").removeClass("disabled");
    });    

  };

}());
