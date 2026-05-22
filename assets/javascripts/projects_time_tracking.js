/* Projects Time Tracking — close/archive guard popup.
 *
 * When a project has open issues the server blocks close and archive actions
 * (ProjectsControllerPatch). This script provides the UX layer: it intercepts
 * close/archive links in capture phase (before rails-ujs) and shows a
 * Redmine-styled modal with the open-issue count instead of navigating.
 *
 * Works on two page types:
 *   1. Project show page (/projects/:id) — open-issue count comes from
 *      #ptt-close-guard-data[data-open-issues] rendered by the sidebar hook.
 *   2. Admin projects list (/admin/projects) — count comes from
 *      tr#project-<id>[data-ptt-open-issues] populated server-side in _list.
 *      Archive links are injected dynamically via AJAX context menus, so
 *      event delegation on document is required (querySelectorAll at load
 *      time would miss them).
 *
 * No external dependencies (no CDN) — plain DOM API.
 */
(function () {
  'use strict';

  // ---------------------------------------------------------------------------
  // Modal helpers
  // ---------------------------------------------------------------------------

  function showGuardModal(message) {
    var overlay = document.getElementById('ptt-close-guard-modal');
    if (!overlay) {
      window.alert(message); // graceful fallback if markup is missing
      return;
    }
    var text = overlay.querySelector('.ptt-close-guard-text');
    if (text) { text.textContent = message; }
    overlay.style.display = 'flex';
  }

  function hideGuardModal() {
    var overlay = document.getElementById('ptt-close-guard-modal');
    if (overlay) { overlay.style.display = 'none'; }
  }

  // Exposed for the inline onclick handler in the modal partial.
  window.pttHideGuardModal = hideGuardModal;

  // ---------------------------------------------------------------------------
  // Count resolution
  // ---------------------------------------------------------------------------

  // Extract project ID from href like /projects/42/archive or /projects/42/close
  var PTT_HREF_RE = /\/projects\/(\d+)\/(?:archive|close)/;

  function pttProjectIdFromHref(href) {
    var m = PTT_HREF_RE.exec(href || '');
    return m ? m[1] : null;
  }

  // Returns open-issue count for the link target, or -1 if unknown.
  function pttOpenCount(href, projectId) {
    // Project show page: single-project data element (authoritative, includes subprojects)
    var data = document.getElementById('ptt-close-guard-data');
    if (data) {
      return parseInt(data.getAttribute('data-open-issues'), 10) || 0;
    }

    // Admin list: per-row data attribute set from server-side batch query
    if (projectId) {
      var row = document.getElementById('project-' + projectId);
      if (row && row.hasAttribute('data-ptt-open-issues')) {
        return parseInt(row.getAttribute('data-ptt-open-issues'), 10) || 0;
      }
    }

    return -1; // unknown — let the browser handle normally
  }

  // Build the modal message for the given count.
  function pttBuildMessage(href, count) {
    // Project show page: pre-built message with correct grammar
    var data = document.getElementById('ptt-close-guard-data');
    if (data) {
      return data.getAttribute('data-message') || String(count);
    }

    // Admin list: substitute count into the server-rendered i18n template
    var tpl = document.getElementById('ptt-guard-msg-template');
    if (tpl) {
      return (tpl.getAttribute('data-template') || '').replace('__COUNT__', String(count));
    }

    return String(count);
  }

  // ---------------------------------------------------------------------------
  // Delegated capture-phase listener
  // Runs before rails-ujs (which uses bubble phase on document), so
  // stopImmediatePropagation() prevents the rails-ujs confirm dialog AND the
  // navigation when we want to show our own modal instead.
  // ---------------------------------------------------------------------------

  document.addEventListener('click', function (e) {
    // Walk up from the click target to find an anchor
    var link = e.target.closest ? e.target.closest('a') : null;
    if (!link) { return; }

    var href = link.getAttribute('href') || '';

    // Only intercept close and archive actions
    if (!/\/(?:archive|close)$/.test(href)) { return; }

    var projectId = pttProjectIdFromHref(href);
    var count = pttOpenCount(href, projectId);

    if (count <= 0) {
      // No open issues (or count unknown) — let the normal flow proceed
      return;
    }

    // Prevent navigation and the rails-ujs confirm
    e.preventDefault();
    e.stopImmediatePropagation();

    showGuardModal(pttBuildMessage(href, count));
  }, true /* capture phase */);

  // ---------------------------------------------------------------------------
  // Modal dismiss: overlay background click and Escape key
  // ---------------------------------------------------------------------------

  document.addEventListener('click', function (e) {
    var overlay = document.getElementById('ptt-close-guard-modal');
    if (overlay && e.target === overlay) { hideGuardModal(); }
  });

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { hideGuardModal(); }
  });

})();
