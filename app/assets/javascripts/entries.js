$( document ).ready(function() {
  
  //options at http://eternicode.github.io/bootstrap-datepicker/
  $('.input-group.date').datepicker({
    format: "yyyy-mm-dd",
    todayHighlight: true,
    autoclose: true,
    todayBtn: "linked"
  });

  $('form').submit(function(){
    $(this).find('input[type=submit]').prop('disabled', true);
    $(this).find('input[type=submit]').addClass('disabled');
  });

  window.onscroll = function(ev) {
    if ((window.innerHeight + window.scrollY) >= 1600) {
      $(".j-back-to-top").fadeIn();
    } else {
      $(".j-back-to-top").fadeOut();
    }
  };

});