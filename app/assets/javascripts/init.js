(function(){
  window.DABBLE = window.DABBLE || {};

  DABBLE.pages = DABBLE.pages || {};

  DABBLE.init = function(){
    var didScroll;
    var lastScrollTop = 0;
    var delta = 20;
    var $nav = $('#app-nav');
    var navbarHeight = $nav.length ? $nav.outerHeight() : 56;

    $(window).scroll(function(){
        didScroll = true;
    });

    setInterval(function() {
      if (didScroll) {
        hasScrolled();
        didScroll = false;
      }
    }, 250);

    function hasScrolled() {
        var st = $(window).scrollTop();

        if(Math.abs(lastScrollTop - st) <= delta)
            return;

        if (st > lastScrollTop && st > navbarHeight && $(window).width() > 768){
            $nav.addClass('nav-up');
            $(".j-back-to-top").fadeOut();
        } else {
            if(st + $(window).height() < $(document).height()) {
                $nav.removeClass('nav-up');
                if ((window.innerHeight + window.scrollY) >= 1600 && $(window).width() > 768) {
                  $(".j-back-to-top").fadeIn();
                }
            }
        }

        lastScrollTop = st;
    }

    if (typeof tippy !== 'undefined') {
      tippy('[rel="popover"]', {
        content: function(reference) {
          return reference.getAttribute('data-content');
        },
        allowHTML: true,
        interactive: true,
        theme: 'light-border',
        placement: 'auto',
        trigger: 'mouseenter focus',
      });

      tippy('[rel="tooltip-mobile-friendly"]', {
        content: function(reference) {
          return reference.getAttribute('title');
        },
        placement: 'top',
        theme: 'light-border',
      });

      if ($(window).width() > 768) {
        var settingsEls = document.querySelectorAll('[rel="popover_settings"]');
        tippy(settingsEls, {
          content: function(reference) {
            return reference.getAttribute('data-content');
          },
          allowHTML: true,
          interactive: true,
          theme: 'light-border',
          placement: 'bottom',
          trigger: 'mouseenter focus',
          showOnCreate: true,
        });

        tippy('[rel="tooltip"]', {
          content: function(reference) {
            return reference.getAttribute('title');
          },
          placement: 'top',
          theme: 'light-border',
        });
      }
    }

    $(document).on('click', "[rel='popover']", function () {
      if (this._tippy) { this._tippy.hide(); }
    });

    $(".j-entry-link").on('click', function() {
      var $entry = $("#entry-"+$(this).attr('data-id'));
      $('body,html').animate({scrollTop: $entry.offset().top - 70}, 600);
      $entry.addClass("pulse");
      setTimeout( function() {
        $entry.removeClass("pulse");
      }, 2000);
    });

    $(".pictureFrame img").unveil(300);

    $('#mobile-menu-toggle').on('click', function() {
      $('#mobile-menu').toggleClass('hidden');
      var expanded = !$('#mobile-menu').hasClass('hidden');
      $(this).attr('aria-expanded', expanded);
    });

    $(document).on('click', '.j-copy-to-clipboard', function(e) {
      e.preventDefault();
      var $btn = $(this);
      var content = $btn.data('content');

      navigator.clipboard.writeText(content).then(function() {
        var originalHtml = $btn.html();
        $btn.html('<i class="fa fa-check"></i> Copied!');
        setTimeout(function() {
          $btn.html(originalHtml);
        }, 2000);
      });
    });

  };

})();
