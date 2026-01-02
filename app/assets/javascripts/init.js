(function(){
  window.DABBLE = window.DABBLE || {};

  DABBLE.pages = DABBLE.pages || {};

  DABBLE.init = function(){
    var didScroll;
    var lastScrollTop = 0;
    var delta = 20;
    var navbarHeight = $('.navbar-fixed-top').outerHeight();

    $(window).scroll(function(event){
        didScroll = true;
    });

    setInterval(function() {
      if (didScroll) {
        hasScrolled();
        didScroll = false;
      }
    }, 250);

    function hasScrolled() {
        var st = $(this).scrollTop();
        
        // Make sure they scroll more than delta
        if(Math.abs(lastScrollTop - st) <= delta)
            return;
        
        // If they scrolled down and are past the navbar, add class .nav-up.
        // This is necessary so you never see what is "behind" the navbar.
        if (st > lastScrollTop && st > navbarHeight && $(window).width() > 768){
            // Scroll Down
            $('.navbar-fixed-top').addClass('nav-up');
            $(".j-back-to-top").fadeOut();
        } else {
            // Scroll Up
            if(st + $(window).height() < $(document).height()) {
                $('.navbar-fixed-top').removeClass('nav-up');
                if ((window.innerHeight + window.scrollY) >= 1600 && $(window).width() > 768) {
                  $(".j-back-to-top").fadeIn();
                }
            }
        }
        
        lastScrollTop = st;
    }

    $("[rel='popover']").popover({
      trigger: "hover",
      container: "body",
      html: true
    });

    $("[rel='tooltip-mobile-friendly']").tooltip({
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

    $(".j-entry-link").click(function(e) {
      var $entry = $("#entry-"+$(this).attr('data-id'));
      $('body,html').animate({scrollTop: $entry.offset().top - 70}, 600);
      $entry.addClass("pulse");
      setTimeout( function() {
        $entry.removeClass("pulse");
      }, 2000);
    });

    
    $(".pictureFrame img").unveil(300);

    $(".navbar-toggle").on("click", function () {
        $(this).toggleClass("active");
    });

  };

})();
