(function(){
  window.DABBLE = {};

  DABBLE.pages = DABBLE.pages || {};

  DABBLE.init = function(){

    $('.j-screenshots a').click(function (e) {
      $('#myModal img').attr('src', $(this).attr('data-img-url'));
    });

    window.onscroll = function(ev) {
      if ((window.innerHeight + window.scrollY) >= 1600) {
        $(".j-back-to-top").fadeIn();
      } else {
        $(".j-back-to-top").fadeOut();
      }
    };

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
    });

  };

})();