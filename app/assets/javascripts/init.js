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

      $("[rel='tooltip']").tooltip({
        container: "body"
      });
    }

    $("[rel='popover']").click(function (e) {
        //e.stopPropagation();
        $(this).popover('hide');
    });

    $(".j-paid").click(function(e) {
      $.cookie('donated', true, { expires: 30, path: '/' });
    });

    $(".j-entry-link").click(function(e) {
      var $entry = $("#entry-"+$(this).attr('data-id'));
      $('body,html').animate({scrollTop: $entry.offset().top - 70}, 600);
    });

    //$.rails.confirm = function(message) { var here = swal({title: "Are you sure?", text: message, type: "error", confirmButtonText: "Delete", showCancelButton: true, cancelButtonText: "No!" }); };

  };

})();