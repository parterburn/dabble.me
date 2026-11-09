// The few interactive pieces the app took from Bootstrap 3's JavaScript:
// the phone menu (collapse), the navbar dropdowns, tooltips, and the
// first-week settings hint (a popover). Markup and class names are unchanged.
(function ($) {
  "use strict";

  var UI = window.UI = {};

  // Collapse: [data-toggle="collapse"][data-target] shows and hides its target.
  $(document).on("click", '[data-toggle="collapse"]', function (e) {
    e.preventDefault();
    var $toggle = $(this);
    var $target = $($toggle.attr("data-target"));
    var open = $target.hasClass("in");
    $target.stop(true, true);
    if (open) {
      $target.slideUp(350, function () { $target.removeClass("in").css("display", ""); });
    } else {
      $target.addClass("in").hide().slideDown(350, function () { $target.css("display", ""); });
    }
    $toggle.attr("aria-expanded", String(!open)).toggleClass("collapsed", open);
  });

  // Dropdowns: [data-toggle="dropdown"] toggles .open on its parent. A click
  // outside or Esc closes it. Opening fires "show.dropdown" on the parent.
  function closeDropdowns($except) {
    $('[data-toggle="dropdown"]').each(function () {
      var $parent = $(this).parent();
      if (!$parent.hasClass("open") || ($except && $parent.is($except))) return;
      $parent.removeClass("open");
      $(this).attr("aria-expanded", "false");
    });
  }

  $(document).on("click", '[data-toggle="dropdown"]', function (e) {
    e.preventDefault();
    var $toggle = $(this);
    var $parent = $toggle.parent();
    var opening = !$parent.hasClass("open");
    closeDropdowns($parent);
    if (opening) {
      $parent.trigger("show.dropdown");
      $toggle.trigger("focus");
    }
    $parent.toggleClass("open", opening);
    $toggle.attr("aria-expanded", String(opening));
  });

  $(document).on("click", function (e) {
    if ($(e.target).closest('[data-toggle="dropdown"]').length) return;
    closeDropdowns();
  });

  // Esc closes; up/down move through the open menu's links.
  $(document).on("keydown", '[data-toggle="dropdown"], .dropdown-menu', function (e) {
    if (!/^(27|38|40)$/.test(e.which)) return;
    var $parent = $(this).closest(".dropdown");
    var $toggle = $parent.find('[data-toggle="dropdown"]');
    e.preventDefault();
    if (e.which === 27) {
      closeDropdowns();
      $toggle.trigger("focus");
      return;
    }
    if (!$parent.hasClass("open")) {
      $toggle.trigger("click");
    }
    var $items = $parent.find(".dropdown-menu li:not(.disabled):visible a");
    if (!$items.length) return;
    var index = $items.index(e.target);
    if (e.which === 38 && index > 0) index--;
    if (e.which === 40 && index < $items.length - 1) index++;
    if (index < 0) index = 0;
    $items.eq(index).trigger("focus");
  });

  // Place a tip above ("top") or below ("bottom") an element, centered on it.
  // This follows Bootstrap's tooltip.js step by step so tips land exactly
  // where they used to: near the right edge a tip narrows to fit rather than
  // shifting, and its arrow moves to keep pointing at the element.
  function place($tip, $el, placement) {
    $tip.css({ top: 0, left: 0, display: "block" }).addClass(placement).appendTo(document.body);
    var rect = $el[0].getBoundingClientRect();
    var pos = { top: rect.top + window.scrollY, left: rect.left + window.scrollX, width: rect.width, height: rect.height };
    var width = $tip[0].offsetWidth;
    var height = $tip[0].offsetHeight;
    var offset = {
      top: placement === "bottom" ? pos.top + pos.height : pos.top - height,
      left: pos.left + pos.width / 2 - width / 2
    };
    $tip.css(offset);

    // Placing it may have narrowed (and so heightened) the tip.
    var actualWidth = $tip[0].offsetWidth;
    var actualHeight = $tip[0].offsetHeight;
    if (placement === "top" && actualHeight !== height) {
      offset.top = offset.top + height - actualHeight;
    }

    // Keep it off the page's left edge.
    var bodyLeft = document.body.getBoundingClientRect().left + window.scrollX;
    var bodyRight = bodyLeft + document.body.getBoundingClientRect().width;
    var delta = 0;
    if (offset.left < bodyLeft) delta = bodyLeft - offset.left;
    else if (offset.left + actualWidth > bodyRight) delta = bodyRight - (offset.left + actualWidth);
    offset.left += delta;
    $tip.css(offset);

    var arrowDelta = delta * 2 - width + actualWidth;
    $tip.find(".tooltip-arrow, .arrow").css("left", arrowDelta ? 50 * (1 - arrowDelta / $tip[0].offsetWidth) + "%" : "");
  }

  // Tooltips: the element's title, shown on hover or focus.
  UI.tooltips = function (selector) {
    $(selector).each(function () {
      var $el = $(this);
      if ($el.data("ui-tooltip")) return;
      $el.data("ui-tooltip", true);
      if ($el.attr("title")) {
        $el.attr("data-original-title", $el.attr("title")).attr("title", "");
      }
      var $tip = null;
      $el.on("mouseenter focusin", function () {
        var text = $el.attr("data-original-title");
        if (!text || $tip) return;
        $tip = $('<div class="tooltip fade" role="tooltip"><div class="tooltip-arrow"></div><div class="tooltip-inner"></div></div>');
        $tip.find(".tooltip-inner").text(text);
        place($tip, $el, "top");
        $tip.addClass("in");
      });
      // Not on click: a tap on a phone fires mouseenter and then click, and the
      // "mobile-friendly" tooltips are meant to show on tap.
      $el.on("mouseleave focusout", function () {
        if ($tip) { $tip.remove(); $tip = null; }
      });
    });
  };

  // Popover: shows the element's data-content (HTML from the server) below it
  // until UI.hidePopover is called.
  UI.popover = function ($el) {
    if (!$el.length || $el.data("ui-popover")) return;
    var $tip = $('<div class="popover fade" role="tooltip"><div class="arrow"></div><div class="popover-content"></div></div>');
    $tip.find(".popover-content").html($el.attr("data-content"));
    place($tip, $el, $el.attr("data-placement") || "bottom");
    $tip.addClass("in");
    $el.data("ui-popover", $tip);
  };

  UI.hidePopover = function ($el) {
    var $tip = $el.data("ui-popover");
    if (!$tip) return;
    $tip.removeClass("in");
    setTimeout(function () { $tip.remove(); }, 150);
    $el.removeData("ui-popover");
  };
})(jQuery);
