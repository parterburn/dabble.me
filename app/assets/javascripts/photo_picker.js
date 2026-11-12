// Photo field on the new and edit entry forms (entries/_photo_picker):
// drag-and-drop or click to browse, thumbnails of the chosen photos with a
// remove button on each, a limit of data-max photos, and an "×" that marks an
// entry's saved photo for removal when the form is saved.
(function() {
  window.DABBLE = window.DABBLE || {};

  var PHOTO_NAME = /\.(jpe?g|png|gif|webp|heic|heif)$/i;

  function isPhoto(file) {
    return /^image\//.test(file.type) || PHOTO_NAME.test(file.name);
  }

  // Lets us rewrite input.files (to merge picks and drop removed photos).
  function canSetFiles() {
    try {
      return typeof DataTransfer !== "undefined" && !!new DataTransfer().items;
    } catch (e) {
      return false;
    }
  }

  function plural(count, word) {
    return count + " " + word + (count === 1 ? "" : "s");
  }

  DABBLE.photoPicker = function(root) {
    if (!root || root.getAttribute("data-photo-picker-ready")) { return; }
    root.setAttribute("data-photo-picker-ready", "true");

    var input = root.querySelector("input[type=file]");
    var drop = root.querySelector(".j-photo-drop");
    var title = root.querySelector(".j-photo-title");
    var count = root.querySelector(".j-photo-count");
    var thumbs = root.querySelector(".j-photo-thumbs");
    var message = root.querySelector(".j-photo-message");
    var current = root.querySelector(".j-photo-current");
    var removed = root.querySelector(".j-photo-removed");
    var removeFlag = root.querySelector(".j-photo-remove-flag");
    var max = parseInt(root.getAttribute("data-max"), 10) || 8;
    var editable = canSetFiles();
    var files = [];
    var previewUrls = [];

    function say(text) {
      message.textContent = text || "";
    }

    function syncInput() {
      if (!editable) { return; }
      var transfer = new DataTransfer();
      files.forEach(function(file) { transfer.items.add(file); });
      input.files = transfer.files;
    }

    function alreadyAdded(file) {
      return files.some(function(other) {
        return other.name === file.name && other.size === file.size && other.lastModified === file.lastModified;
      });
    }

    function addFiles(list) {
      var notPhotos = 0;
      var overLimit = 0;
      Array.prototype.forEach.call(list, function(file) {
        if (!isPhoto(file)) { notPhotos += 1; return; }
        if (alreadyAdded(file)) { return; }
        if (files.length >= max) { overLimit += 1; return; }
        files.push(file);
      });

      var notes = [];
      if (overLimit) { notes.push("You can add up to " + max + " photos, so " + plural(overLimit, "photo") + " didn't fit."); }
      if (notPhotos) { notes.push(plural(notPhotos, "file") + " skipped: only photos can be added."); }
      say(notes.join(" "));

      syncInput();
      render();
    }

    function removeAt(index) {
      files.splice(index, 1);
      say("");
      syncInput();
      render();
    }

    function placeholder(file) {
      var tile = document.createElement("div");
      tile.className = "photo-picker__placeholder";
      var ext = (file.name.split(".").pop() || "").toUpperCase();
      tile.innerHTML = '<span class="slab-icon slab-icon--image" aria-hidden="true"></span>';
      var label = document.createElement("span");
      label.textContent = ext || "Photo";
      tile.appendChild(label);
      return tile;
    }

    function render() {
      previewUrls.forEach(function(url) { URL.revokeObjectURL(url); });
      previewUrls = [];
      thumbs.innerHTML = "";

      files.forEach(function(file, index) {
        var item = document.createElement("li");
        item.className = "photo-picker__thumb";
        item.title = file.name;

        var url = URL.createObjectURL(file);
        previewUrls.push(url);
        var img = document.createElement("img");
        img.alt = file.name;
        img.src = url;
        // Most browsers can't preview HEIC; show a tile instead.
        img.onerror = function() { item.replaceChild(placeholder(file), img); };
        item.appendChild(img);

        if (editable) {
          var remove = document.createElement("button");
          remove.type = "button";
          remove.className = "photo-picker__remove";
          remove.setAttribute("aria-label", "Remove " + file.name);
          remove.title = "Remove photo";
          remove.innerHTML = "&times;";
          remove.addEventListener("click", function() { removeAt(index); });
          item.appendChild(remove);
        }
        thumbs.appendChild(item);
      });

      var full = files.length >= max;
      drop.classList.toggle("is-compact", files.length > 0);
      if (!current || current.hidden) { drop.hidden = full; }
      title.textContent = files.length ? "Add more photos" : "Add photos";
      count.textContent = files.length ? files.length + " of " + max + " photos" : "";
    }

    input.addEventListener("change", function() {
      var picked = Array.prototype.slice.call(input.files);
      if (!editable) { files = []; }
      addFiles(picked);
    });

    ["dragenter", "dragover"].forEach(function(type) {
      drop.addEventListener(type, function(event) {
        event.preventDefault();
        drop.classList.add("is-dragging");
      });
    });
    ["dragleave", "dragend", "drop"].forEach(function(type) {
      drop.addEventListener(type, function() { drop.classList.remove("is-dragging"); });
    });
    drop.addEventListener("drop", function(event) {
      event.preventDefault();
      if (!editable) {
        say("Drag and drop isn't supported in this browser. Click to choose photos instead.");
        return;
      }
      addFiles(event.dataTransfer.files);
    });

    // A photo dropped just outside the box would otherwise open in the tab
    // and lose the entry being written.
    ["dragover", "drop"].forEach(function(type) {
      document.addEventListener(type, function(event) {
        var types = event.dataTransfer && event.dataTransfer.types;
        var hasFiles = types && Array.prototype.indexOf.call(types, "Files") !== -1;
        if (hasFiles && !drop.contains(event.target)) { event.preventDefault(); }
      });
    });

    if (current) {
      root.querySelector(".j-photo-remove-current").addEventListener("click", function() {
        removeFlag.value = "1";
        current.hidden = true;
        removed.hidden = false;
        drop.hidden = files.length >= max;
      });
      root.querySelector(".j-photo-undo").addEventListener("click", function() {
        removeFlag.value = "0";
        current.hidden = false;
        removed.hidden = true;
        // Keeping the saved photo: drop any new picks so it isn't replaced.
        files = [];
        if (!editable) { input.value = ""; }
        syncInput();
        render();
        say("");
        drop.hidden = true;
      });
    }

    render();
  };

  DABBLE.photoPickers = function() {
    Array.prototype.forEach.call(document.querySelectorAll(".j-photo-picker"), DABBLE.photoPicker);
  };
})();
