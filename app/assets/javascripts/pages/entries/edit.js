(function(){
  window.DABBLE.pages.Entries_edit = window.DABBLE.pages.Entries_update = function(){

    $('.input-group.date').datepicker({
      format: "MM d yyyy",
      todayHighlight: true,
      keyboardNavigation: false,
      autoclose: true,
      endDate: new Date(),
      todayBtn: "linked"
    });

    DABBLE.pages.Entries_new.call();

  };

}());