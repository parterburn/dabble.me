// "Reflect on this entry" (the magic wand on an entry). Asks the server for a
// one-off AI reflection and shows it in a native <dialog>. Nothing is saved.
// Plain JS on purpose: no new code on end-of-life Bootstrap 3 or jQuery.
(function() {
  var dialog, body, dateLine, pending;

  function build() {
    dialog = document.createElement('dialog');
    dialog.className = 's-reflection-dialog';
    dialog.setAttribute('aria-labelledby', 'reflection-title');
    dialog.innerHTML =
      '<div class="s-reflection-header">' +
        '<h4 id="reflection-title">Reflection</h4>' +
        '<button type="button" class="close" aria-label="Close"><span aria-hidden="true">&times;</span></button>' +
      '</div>' +
      '<div class="s-reflection-content">' +
        '<p class="s-reflection-date"></p>' +
        '<div class="s-reflection-body" aria-live="polite"></div>' +
        '<p class="s-reflection-note"><i class="fa fa-lock"></i> Written by AI from this entry. It isn\'t saved, and your entries aren\'t used to train AI models.</p>' +
      '</div>';
    document.body.appendChild(dialog);

    body = dialog.querySelector('.s-reflection-body');
    dateLine = dialog.querySelector('.s-reflection-date');
    dialog.querySelector('.close').addEventListener('click', function() { dialog.close(); });
    // A click on the backdrop lands on the dialog element itself.
    dialog.addEventListener('click', function(e) { if (e.target === dialog) dialog.close(); });
    dialog.addEventListener('close', function() { if (pending) pending.abort(); });
  }

  function showError(message) {
    var p = document.createElement('p');
    p.className = 'text-danger';
    p.textContent = message || 'Something went wrong. Try again in a minute.';
    body.replaceChildren(p);
  }

  document.addEventListener('click', function(e) {
    var link = e.target.closest('.j-reflect');
    if (!link) return;
    e.preventDefault();
    if (!dialog) build();

    dateLine.textContent = link.dataset.date;
    body.innerHTML = '<p class="s-reflection-loading"><i class="fa fa-spinner fa-spin"></i> Reflecting&hellip;</p>';
    dialog.showModal();

    var request = pending = new AbortController();
    var token = document.querySelector('meta[name="csrf-token"]');
    fetch(link.dataset.url, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'Accept': 'application/json', 'X-CSRF-Token': token ? token.content : '' },
      signal: request.signal
    }).then(function(response) {
      return response.json().catch(function() { return {}; }).then(function(data) {
        // The server sanitizes this HTML (EntriesController#reflection).
        if (response.ok && data.html) body.innerHTML = data.html;
        else showError(data.error);
      });
    }).catch(function(error) {
      if (error.name !== 'AbortError') showError();
    }).then(function() {
      if (pending === request) pending = null;
    });
  });
})();
