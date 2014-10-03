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

    $("[rel='tooltip']").tooltip({
      container: "body"
    });

    //$.rails.confirm = function(message) { var here = swal({title: "Are you sure?", text: message, type: "error", confirmButtonText: "Delete", showCancelButton: true, cancelButtonText: "No!" }); };

  };

})();