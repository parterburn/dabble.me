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
            // Scroll Down. Web apps keep the navbar in place, since iOS blurs
            // the top edge without it.
            if (!document.documentElement.classList.contains('web-app')) {
                $('.navbar-fixed-top').addClass('nav-up');
            }
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

    UI.tooltips("[rel='tooltip-mobile-friendly']");

    if ($(window).width() > 768) {
      // First-week hint about when emails arrive. It points at the account
      // menu, so it goes away once that menu is opened, by click or hover.
      var $settingsHint = $("[rel='popover_settings']");
      UI.popover($settingsHint);
      $settingsHint.on('show.dropdown mouseenter', function() { UI.hidePopover($settingsHint); });

      UI.tooltips("[rel='tooltip']");
    }

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

    $(document).on('click', '.j-copy-to-clipboard', function(e) {
      e.preventDefault();
      var $btn = $(this);
      var content = $btn.data('content');

      navigator.clipboard.writeText(content).then(function() {
        var originalHtml = $btn.html();
        $btn.html('<span class="slab-icon slab-icon--clipboard" aria-hidden="true"></span> Copied!');
        setTimeout(function() {
          $btn.html(originalHtml);
        }, 2000);
      });
    });

  };

})();
