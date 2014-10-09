(function(){
  window.DABBLE = {};

  DABBLE.pages = DABBLE.pages || {};

  DABBLE.init = function(){

    window.onscroll = function(ev) {
      if ((window.innerHeight + window.scrollY) >= 1600) {
        $(".j-back-to-top").fadeIn();
      } else {
        $(".j-back-to-top").fadeOut();
      }
    };

    $("[rel='popover']").popover({
      trigger: "hover",
      container: "body"
    });

    if ($(window).width() > 768) {
      $("[rel='popover_settings']").popover({
        trigger: "hover",
        container: "body",
        html: true
      }).popover('show');
    }

    setTimeout(function(){
      $("[rel='popover_settings']").popover('hide');
    }, 10000);

    $(".j-paid").click(function(e) {
      $.cookie('donated', true, { expires: 30, path: '/' });
    });

    $("[rel='tooltip']").tooltip({
      container: "body"
    });

    //$.rails.confirm = function(message) { var here = swal({title: "Are you sure?", text: message, type: "error", confirmButtonText: "Delete", showCancelButton: true, cancelButtonText: "No!" }); };

    $(window).on('hashchange', function() {
      var $entry = $(window.location.hash);
      window.location.hash = "";
      if ($entry.length > 0) {
        $('body,html').animate({scrollTop: $entry.offset().top - 70}, 600);
      }
    }).trigger('hashchange');    

  };

})();