(function () {
  var DRAFT_KEY = 'dabbleWebmcpDraft';

  function modelContext() {
    if (document.modelContext && typeof document.modelContext.registerTool === 'function') {
      return document.modelContext;
    }
    if (navigator.modelContext && typeof navigator.modelContext.registerTool === 'function') {
      return navigator.modelContext;
    }
    return null;
  }

  function config() {
    var node = document.getElementById('dabble-webmcp-config');
    if (!node || !node.textContent) {
      return { tools: [] };
    }
    try {
      return JSON.parse(node.textContent);
    } catch (error) {
      return { tools: [] };
    }
  }

  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute('content') : '';
  }

  function formToolNames() {
    return Array.prototype.map.call(document.querySelectorAll('form[toolname]'), function (form) {
      return form.getAttribute('toolname');
    });
  }

  function toolResult(text, isError) {
    return {
      content: [{ type: 'text', text: text }],
      isError: !!isError
    };
  }

  function showStatus(message) {
    var el = document.getElementById('dabble-webmcp-status');
    if (!el) {
      el = document.createElement('div');
      el.id = 'dabble-webmcp-status';
      el.setAttribute('role', 'status');
      document.body.appendChild(el);
    }
    el.textContent = message;
    el.hidden = false;
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function toHtmlParagraphs(text) {
    return String(text).split(/\n{2,}/).map(function (part) {
      return '<p>' + escapeHtml(part).replace(/\n/g, '<br>') + '</p>';
    }).join('');
  }

  function humanDate(iso) {
    if (!iso) {
      return '';
    }
    var parts = String(iso).split('-');
    if (parts.length !== 3) {
      return iso;
    }
    var date = new Date(Date.UTC(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])));
    return date.toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
  }

  function dayPath(iso) {
    var parts = String(iso).split('-');
    if (parts.length !== 3) {
      return null;
    }
    return '/entries/' + Number(parts[0]) + '/' + Number(parts[1]) + '/' + Number(parts[2]);
  }

  function writeForm() {
    return document.querySelector('form[toolname="write_journal_entry"], form[toolname="update_journal_entry"]');
  }

  function fillWriteForm(input) {
    var form = writeForm();
    if (!form) {
      return false;
    }

    var dateField = form.querySelector('[name="entry[date]"]');
    var bodyField = form.querySelector('[name="entry[entry]"]');
    if (dateField && input.date) {
      dateField.value = humanDate(input.date);
      dateField.dispatchEvent(new Event('input', { bubbles: true }));
      dateField.dispatchEvent(new Event('change', { bubbles: true }));
    }
    if (bodyField && input.body) {
      var html = toHtmlParagraphs(input.body);
      if (window.jQuery && window.jQuery.fn && window.jQuery.fn.summernote && window.jQuery(bodyField).next('.note-editor').length) {
        window.jQuery(bodyField).summernote('code', html);
      } else {
        bodyField.value = input.body;
      }
      bodyField.dispatchEvent(new Event('input', { bubbles: true }));
    }
    form.classList.add('dabble-webmcp-drafted');
    if (form.scrollIntoView) {
      form.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
    return true;
  }

  function applyPendingDraft() {
    var raw = sessionStorage.getItem(DRAFT_KEY);
    if (!raw || !writeForm()) {
      return;
    }
    try {
      var draft = JSON.parse(raw);
      if (fillWriteForm(draft)) {
        sessionStorage.removeItem(DRAFT_KEY);
        showStatus('Agent draft ready. Review the entry and click Create Entry if you want to save it.');
      }
    } catch (error) {
      sessionStorage.removeItem(DRAFT_KEY);
    }
  }

  async function callJournal(action, input) {
    var response = await fetch('/webmcp/journal/' + action, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-CSRF-Token': csrfToken()
      },
      body: JSON.stringify(input || {})
    });
    var payload = await response.json();
    if (payload && payload.data && !payload.isError) {
      showStatus(statusFor(action, payload.data));
    }
    return payload;
  }

  function statusFor(action, data) {
    if (action === 'search') {
      return 'Agent searched the journal for “' + (data.query || '') + '” — ' + (data.total_matches || 0) + ' match(es).';
    }
    if (action === 'list') {
      return 'Agent listed ' + ((data.entries && data.entries.length) || 0) + ' of ' + (data.total_matches || 0) + ' journal entries.';
    }
    if (action === 'analyze') {
      return 'Agent summarized journaling patterns across ' + (data.total_entries || 0) + ' entries.';
    }
    return 'Agent used a Dabble Me journal tool.';
  }

  function sessionFromConfig(cfg) {
    return {
      signed_in: !!cfg.signedIn,
      first_name: cfg.firstName || null,
      is_pro: !!cfg.isPro,
      can_search: !!cfg.isPro,
      can_write: !!cfg.isPro,
      today: cfg.today,
      write_path: cfg.paths && cfg.paths.write,
      search_path: cfg.paths && cfg.paths.search,
      note: cfg.signedIn
        ? (cfg.isPro
          ? 'This tab is signed in with PRO. Search, list, analyze, and draft are available. Do not submit the write form for the user.'
          : 'This tab is signed in. Listing and opening days work; search and drafts need PRO.')
        : 'This tab is signed out. Use the log_in form, then reload so journal tools appear.'
    };
  }

  function canRegister(tool, cfg) {
    if (tool.requireSignedIn && !cfg.signedIn) {
      return false;
    }
    if (tool.requirePro && !cfg.isPro) {
      return false;
    }
    return true;
  }

  function executorFor(tool, cfg) {
    if (tool.kind === 'static') {
      var result = tool.result || '';
      return async function () {
        return toolResult(result, false);
      };
    }

    if (tool.name === 'get_journal_session') {
      return async function () {
        if (!cfg.signedIn) {
          return toolResult(JSON.stringify(sessionFromConfig(cfg), null, 2), false);
        }
        return callJournal('session', {});
      };
    }

    if (tool.kind === 'session') {
      return async function (input) {
        return callJournal(tool.action, input || {});
      };
    }

    if (tool.name === 'open_journal_day') {
      return async function (input) {
        var path = dayPath(input && input.date);
        if (!path) {
          return toolResult('date must be YYYY-MM-DD.', true);
        }
        showStatus('Opening ' + path + ' for the user.');
        window.location.assign(path);
        return null;
      };
    }

    if (tool.name === 'open_search_page') {
      return async function (input) {
        var path = '/search';
        if (input && input.query) {
          path += '?search%5Bterm%5D=' + encodeURIComponent(input.query);
        }
        showStatus('Opening search for the user.');
        window.location.assign(path);
        return null;
      };
    }

    if (tool.name === 'open_write_page') {
      return async function () {
        showStatus('Opening the write page for the user.');
        window.location.assign((cfg.paths && cfg.paths.write) || '/entries/new');
        return null;
      };
    }

    if (tool.name === 'draft_journal_entry') {
      return async function (input) {
        var draft = {
          body: input && input.body,
          date: (input && input.date) || cfg.today
        };
        if (!draft.body) {
          return toolResult('body is required.', true);
        }
        if (fillWriteForm(draft)) {
          showStatus('Draft filled. Ask the user to review and click Create Entry. Do not submit the form.');
          return toolResult(JSON.stringify({
            drafted: true,
            submitted: false,
            date: draft.date,
            message: 'The write form is filled. Leave Create Entry for the user.'
          }, null, 2), false);
        }
        sessionStorage.setItem(DRAFT_KEY, JSON.stringify(draft));
        showStatus('Opening the write page with a draft for the user to review.');
        window.location.assign((cfg.paths && cfg.paths.write) || '/entries/new');
        return null;
      };
    }

    return async function () {
      return toolResult('This WebMCP tool is not available on this page.', true);
    };
  }

  async function registerTool(context, tool, declared, cfg) {
    if (!tool || !tool.name || declared.indexOf(tool.name) !== -1) {
      return;
    }
    if (!canRegister(tool, cfg)) {
      return;
    }

    await context.registerTool({
      name: tool.name,
      description: tool.description,
      inputSchema: tool.inputSchema || { type: 'object', properties: {} },
      annotations: tool.annotations || { readOnlyHint: true },
      execute: executorFor(tool, cfg)
    });
  }

  async function registerTools() {
    applyPendingDraft();
    var context = modelContext();
    if (!context) {
      return;
    }

    var cfg = config();
    var declared = formToolNames();
    var tools = cfg.tools || [];
    for (var i = 0; i < tools.length; i += 1) {
      await registerTool(context, tools[i], declared, cfg);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function () {
      registerTools();
    });
  } else {
    registerTools();
  }
})();
