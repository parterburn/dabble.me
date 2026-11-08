// "Reflect on this entry" (the magic wand on an entry). Asks the server for a
// one-off AI reflection and shows it in a modal. Nothing is saved.
(function(){
  var MODAL_HTML =
    '<div class="modal fade s-reflection-modal" id="reflection-modal" tabindex="-1" role="dialog" aria-labelledby="reflection-modal-title">' +
      '<div class="modal-dialog" role="document">' +
        '<div class="modal-content">' +
          '<div class="modal-header">' +
            '<button type="button" class="close" data-dismiss="modal" aria-label="Close"><span aria-hidden="true">&times;</span></button>' +
            '<h4 class="modal-title" id="reflection-modal-title">Reflection</h4>' +
          '</div>' +
          '<div class="modal-body">' +
            '<p class="s-reflection-date"></p>' +
            '<div class="s-reflection-body" aria-live="polite"></div>' +
            '<p class="s-reflection-note"><i class="fa fa-lock"></i> Written by AI from this entry. It isn\'t saved, and your entries aren\'t used to train AI models.</p>' +
          '</div>' +
        '</div>' +
      '</div>' +
    '</div>';

  var pending = null;

  function modal() {
    var $modal = $('#reflection-modal');
    if (!$modal.length) {
      $modal = $(MODAL_HTML).appendTo('body');
      $modal.on('hidden.bs.modal', function() {
        if (pending) { pending.abort(); pending = null; }
      });
    }
    return $modal;
  }

  function showMessage($body, text, className) {
    $body.empty().append($('<p>').addClass(className).text(text));
  }

  $(document).on('click', '.j-reflect', function(e) {
    e.preventDefault();
    if (pending) return;

    var $link = $(this);
    var $modal = modal();
    var $body = $modal.find('.s-reflection-body');

    $modal.find('.s-reflection-date').text($link.data('date'));
    $body.empty().append('<p class="s-reflection-loading"><i class="fa fa-spinner fa-spin"></i> Reflecting&hellip;</p>');
    $modal.modal('show');

    pending = $.ajax({
      url: $link.data('url'),
      method: 'POST',
      dataType: 'json',
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') }
    }).done(function(data) {
      $body.html(data.html);
    }).fail(function(xhr, status) {
      if (status === 'abort') return;
      var error = xhr.responseJSON && xhr.responseJSON.error;
      showMessage($body, error || 'Something went wrong. Try again in a minute.', 'text-danger');
    }).always(function() {
      pending = null;
    });
  });
})();
