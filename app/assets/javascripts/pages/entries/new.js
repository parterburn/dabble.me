(function(){
  window.DABBLE.pages.Entries_new = function(){

    $('.input-group.date').datepicker({
      format: "yyyy-mm-dd",
      todayHighlight: true,
      autoclose: true,
      todayBtn: "linked"
    });

    var summer_note = $('#entry_entry');
    summer_note.summernote({
      mode: 'text/html',
      height: 300,
      theme: 'flatly',
      focus: true,
      toolbar: [["fontsize", ["fontsize"]], ["style", ["bold", "italic", "underline", "clear"]], ["layout", ["ul", "ol"]], ['insert', ['link']], ['misc', ['fullscreen', 'codeview']]]
    });

    summer_note.code(summer_note.val());
    summer_note.closest('form').submit(function() {
      summer_note.val(summer_note.code());
      return true;
    });

  };

}());