// An entry's photo, large. A click on the photo opens it over the page in a native <dialog>
// (Esc, the X, or a click on the dark around the photo closes it); a click on the large photo opens the
// file in a new tab, which is where the first click used to go. Without this script the photo
// is still that link. Plain JS on purpose: no new code on jQuery.
(function() {
  var dialog, link, image;

  function build() {
    dialog = document.createElement('dialog');
    dialog.className = 's-photo-viewer';
    dialog.setAttribute('aria-label', 'Photo');
    // A click on the backdrop closes it, where the browser does that itself.
    dialog.setAttribute('closedby', 'any');
    dialog.innerHTML =
      '<button type="button" class="s-photo-viewer-close" aria-label="Close"><span aria-hidden="true">&times;</span></button>' +
      '<a class="s-photo-viewer-link" target="_blank" rel="noopener" title="Open in a new tab"><img alt=""></a>';
    document.body.appendChild(dialog);

    link = dialog.querySelector('.s-photo-viewer-link');
    image = link.querySelector('img');
    dialog.querySelector('.s-photo-viewer-close').addEventListener('click', function() { dialog.close(); });
    // Where it doesn't (Safari, for now): a click on the backdrop lands on the dialog
    // element itself, outside its box (the box is only as big as the photo).
    if (!('closedBy' in HTMLDialogElement.prototype)) {
      dialog.addEventListener('click', function(e) {
        if (e.target !== dialog) return;
        var box = dialog.getBoundingClientRect();
        var inside = box.top <= e.clientY && e.clientY <= box.bottom && box.left <= e.clientX && e.clientX <= box.right;
        if (!inside) dialog.close();
      });
    }
    // Not left loading behind the page once it's closed.
    dialog.addEventListener('close', function() { image.removeAttribute('src'); });
  }

  document.addEventListener('click', function(e) {
    var opener = e.target.closest && e.target.closest('.pictureFrame > a');
    // A new tab or window asked for (Cmd, Ctrl, Shift, a middle click): the link as it is.
    if (!opener || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (!window.HTMLDialogElement) return;
    e.preventDefault();
    if (!dialog) build();

    var shown = opener.querySelector('img');
    // What's on the page already, at once; then the file itself, which is sharper.
    image.src = (shown && (shown.currentSrc || shown.src)) || opener.href;
    image.alt = (shown && shown.alt) || '';
    link.href = opener.href;
    var full = new Image();
    full.onload = function() { if (dialog.open && link.href === opener.href) image.src = opener.href; };
    full.src = opener.href;
    dialog.showModal();
  });
})();
