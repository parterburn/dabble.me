// "Reflect on this entry" (the sparkles button on an entry). Opens a native
// <dialog> that explains the feature, and only after "Generate Reflection" is
// pressed asks the server for a one-off AI reflection. Nothing is saved.
// Plain JS on purpose: no new code on jQuery.
(function() {
  var dialog, body, dateLine, note, pending, url;

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
        '<p class="s-reflection-note"><span class="slab-icon slab-icon--lock" aria-hidden="true"></span> Written by AI from this entry. It isn\'t saved, and your entries aren\'t used to train AI models.</p>' +
      '</div>';
    document.body.appendChild(dialog);

    body = dialog.querySelector('.s-reflection-body');
    dateLine = dialog.querySelector('.s-reflection-date');
    note = dialog.querySelector('.s-reflection-note');
    dialog.querySelector('.close').addEventListener('click', function() { dialog.close(); });
    // A click on the backdrop lands on the dialog element itself.
    dialog.addEventListener('click', function(e) {
      if (e.target === dialog) dialog.close();
      else if (e.target.closest('.j-generate-reflection')) generate();
    });
    dialog.addEventListener('close', function() { if (pending) pending.abort(); });
  }

  // What the feature does and where the entry goes, before anything is sent.
  // Matches the AI section of the privacy policy.
  function showIntro() {
    note.hidden = true;
    body.innerHTML =
      '<div class="s-reflection-intro">' +
        '<p>Get a short reflection on this entry: a note on how it feels, an observation or two, and one question to think about.</p>' +
        '<p>To write it, Dabble Me sends this entry to Anthropic, the maker of Claude, with its photo if it has one and short excerpts of a few related entries for context. ' +
        'The reflection is shown here and not saved, and Anthropic doesn\'t use your entries to train its models.</p>' +
        '<button type="button" class="btn btn-primary j-generate-reflection" autofocus>' +
          '<span class="slab-icon slab-icon--sparkles" aria-hidden="true"></span> Generate Reflection' +
        '</button>' +
      '</div>';
  }

  function showError(message) {
    var p = document.createElement('p');
    p.className = 'text-danger';
    p.textContent = message || 'Something went wrong. Try again in a minute.';
    body.replaceChildren(p);
  }

  function generate() {
    note.hidden = false;
    body.innerHTML = '<p class="s-reflection-loading"><span class="slab-icon slab-icon--spinner slab-icon--spin" aria-hidden="true"></span> Reflecting&hellip;</p>';

    var request = pending = new AbortController();
    var token = document.querySelector('meta[name="csrf-token"]');
    fetch(url, {
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
  }

  document.addEventListener('click', function(e) {
    var link = e.target.closest('.j-reflect');
    if (!link) return;
    e.preventDefault();
    if (!dialog) build();

    url = link.dataset.url;
    dateLine.textContent = link.dataset.date;
    showIntro();
    dialog.showModal();
  });
})();
