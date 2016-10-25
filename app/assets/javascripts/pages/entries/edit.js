(function(){
  window.DABBLE.pages.Entries_edit = window.DABBLE.pages.Entries_update = function(){

    var tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    $.extend($.fn.pickadate.defaults, {
      format: 'mmmm d, yyyy',
      selectYears: true,
      selectMonths: true,
      max: tomorrow
    })

    $('.pickadate').pickadate();

    DABBLE.pages.Entries_new.call();

  };

}());