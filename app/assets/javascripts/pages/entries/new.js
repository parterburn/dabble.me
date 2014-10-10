(function(){
  window.DABBLE.pages.Entries_new = window.DABBLE.pages.Entries_create = function(){

    $(".j-filepicker-remove").click(function( event ) {
      event.preventDefault();
      $("#entry_image_url").val("");
      $(".j-filepicker-preview").slideUp();
    });

    var summer_note = $('#entry_entry');
    summer_note.summernote({
      mode: 'text/html',
      height: 300,
      theme: 'flatly',
      focus: true,
      toolbar: [["style", ["bold", "italic", "underline", "clear"]], ["layout", ["ul", "ol"]], ['insert', ['link']], ['misc', ['fullscreen', 'codeview']]]
    });

    summer_note.code(summer_note.val());
    summer_note.closest('form').submit(function() {
      summer_note.val(summer_note.code());
      return true;
    });

    $('form').submit(function(){
      $(this).find('input[type=submit]').prop('disabled', true);
      $(this).find('input[type=submit]').addClass('disabled');
      $(".navbar-brand i.fa-spinner").addClass("fa-spin");
    });

  };

}());

function onPhotoUpload(event) {
  console.log(event);
  $(".j-filepicker-preview").slideUp();
}