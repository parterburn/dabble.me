(function(){
  window.DABBLE.pages.Entries_new = window.DABBLE.pages.Entries_create = function(){

    $(".j-filepicker-remove").click(function( event ) {
      event.preventDefault();
      $("#entry_image_url").val("");
      $(".j-filepicker-preview").slideUp();
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