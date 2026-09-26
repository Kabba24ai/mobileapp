// Dispatch offline Phase 5 — the local Terms & Conditions signing page.
//
// The agreement body arrives as data (window.kabbaTermsPayload.body), is parsed
// in an INERT document (DOMParser never runs scripts) and REBUILT, node by node,
// into this page: nothing active survives, and no human-readable wording is
// lost. The page's Content-Security-Policy is the second wall: no script but
// the two nonce-tagged ones, no inline handlers, no javascript: URLs, no
// network, no frames. The app's own approval checkboxes and sign button replace
// the renderer's inert markers.
//
// Rebuilding (Phase 5 hardening — the customer must see every word they sign):
//   • removed with their content — never text a reader of the web page sees,
//     or executable: script, template, noscript (the web page runs scripts, so
//     it never shows it), frame, sources/tracks, link/meta/base, title, area;
//   • embedded content the phone cannot load (no network) never vanishes
//     silently: an iframe, embed, audio or video becomes a visible placeholder,
//     a remote image its alt text or a placeholder, an object its fallback
//     content plus a placeholder;
//   • made inert, their wording kept — a form becomes a plain block, a button
//     or a link plain text (so an approval inside one stays tappable), an
//     applet/dialog/unknown wrapper just its content, a textarea its text;
//   • form controls keep their MEANING as text — a text or button input its
//     visible value (a submit/reset with none its default label), a checkbox
//     or radio ☑/☐ or ◉/○, a select every option with the selected one ◉;
//   • SVG and MathML → their visible text only (never the graphic, never its
//     scripts or handlers; an SVG <title>/<desc> is a tooltip, not shown);
//   • on every element kept: no on* handler, no URL attribute (except an
//     inline data: image), no target/for/form/popover wiring, no style url().
// Sanitizing is presentation only — the frozen agreement and its identity are
// never changed.
(function () {
  'use strict';

  var payload = window.kabbaTermsPayload || {};
  var REMOVE = ['script', 'template', 'noscript', 'frame', 'frameset', 'source', 'track', 'param', 'link', 'meta', 'base',
    'title', 'head', 'area', 'datalist'];
  var EMBEDDED = ['iframe', 'embed', 'audio', 'video'];
  var IMAGE_NOT_SHOWN = '[Image not shown on this phone]';
  var EMBED_NOT_SHOWN = '[Embedded content not shown on this phone]';
  var TEXT_ONLY = ['svg', 'math'];
  var NOT_SHOWN_IN_GRAPHICS = ['title', 'desc', 'metadata', 'script', 'style', 'annotation', 'annotation-xml'];
  var INERT = { form: 'div', button: 'span', a: 'span', object: 'span', applet: 'span', dialog: 'div', portal: 'span',
    slot: 'span', map: 'span', optgroup: 'span', select: 'span', label: 'span', fieldset: 'div', legend: 'div' };
  var URL_ATTRIBUTES = ['href', 'src', 'srcset', 'action', 'formaction', 'xlink:href', 'data', 'poster', 'background',
    'ping', 'lowsrc', 'dynsrc', 'codebase', 'cite', 'longdesc', 'usemap', 'manifest', 'imagesrcset'];
  var DROPPED_ATTRIBUTES = ['target', 'formtarget', 'contenteditable', 'autofocus', 'srcdoc', 'for', 'form', 'popover',
    'popovertarget', 'popovertargetaction', 'download', 'name', 'tabindex', 'accesskey', 'http-equiv', 'is'];
  var TEXT_INPUTS_HIDDEN = ['hidden', 'file', 'password', 'range', 'color'];

  function each(list, fn) { Array.prototype.slice.call(list).forEach(fn); }

  function inertText(className, text) {
    var span = document.createElement('span');
    span.className = className;
    span.textContent = text;
    return span;
  }

  // The visible wording of an SVG or MathML subtree, as plain text.
  function graphicText(el) {
    var parts = [];
    (function walk(node) {
      if (node.nodeType === 3) { parts.push(node.nodeValue); return; }
      if (node.nodeType !== 1 || NOT_SHOWN_IN_GRAPHICS.indexOf(node.localName.toLowerCase()) !== -1) { return; }
      each(node.childNodes, walk);
      parts.push(' ');
    })(el);
    return parts.join('').replace(/\s+/g, ' ').trim();
  }

  function copySafeAttributes(from, to) {
    var isImage = to.tagName === 'IMG';
    each(from.attributes, function (attribute) {
      var name = attribute.name.toLowerCase();
      var value = (attribute.value || '').trim().toLowerCase();
      if (name.indexOf('on') === 0 || DROPPED_ATTRIBUTES.indexOf(name) !== -1) { return; }
      if (URL_ATTRIBUTES.indexOf(name) !== -1 && !(isImage && name === 'src' && value.indexOf('data:image/') === 0)) { return; }
      if (name === 'style' && /url\s*\(|expression\s*\(/i.test(value)) { return; }
      try { to.setAttribute(attribute.name, attribute.value); } catch (e) { /* an attribute name HTML can't carry */ }
    });
  }

  function rebuildChildren(from, to) {
    each(from.childNodes, function (child) {
      var clean = rebuild(child);
      if (clean) { to.appendChild(clean); }
    });
    return to;
  }

  // One node of the parsed agreement → its inert equivalent in THIS document (or null).
  function rebuild(node) {
    if (node.nodeType === 3) { return document.createTextNode(node.nodeValue); }
    if (node.nodeType !== 1) { return null; } // comments, processing instructions
    var tag = node.localName.toLowerCase();

    if (REMOVE.indexOf(tag) !== -1) { return null; }
    if (EMBEDDED.indexOf(tag) !== -1) { return inertText('kabba-inert-placeholder', EMBED_NOT_SHOWN); }
    if (TEXT_ONLY.indexOf(tag) !== -1) {
      var words = graphicText(node);
      return words ? inertText('kabba-inert-text', words) : null;
    }
    if (tag === 'style') {
      if (/@import|url\s*\(/i.test(node.textContent || '')) { return null; }
      var style = document.createElement('style');
      style.textContent = node.textContent;
      return style;
    }
    if (tag === 'input') {
      var type = (node.getAttribute('type') || 'text').toLowerCase();
      var on = node.hasAttribute('checked');
      if (type === 'checkbox') { return inertText('kabba-inert-mark', on ? '☑' : '☐'); }
      if (type === 'radio') { return inertText('kabba-inert-mark', on ? '◉' : '○'); }
      if (type === 'image') {
        var inputAlt = (node.getAttribute('alt') || '').trim();
        return inertText('kabba-inert-placeholder', inputAlt ? '[Image not shown on this phone: ' + inputAlt + ']' : IMAGE_NOT_SHOWN);
      }
      var fallback = { submit: 'Submit', reset: 'Reset' }[type] || '';
      var shown = TEXT_INPUTS_HIDDEN.indexOf(type) === -1 ? (node.getAttribute('value') || node.getAttribute('placeholder') || fallback) : '';
      return shown ? inertText('kabba-inert-control', shown) : null;
    }
    if (tag === 'option') {
      var label = node.getAttribute('label') || node.textContent || '';
      var chosen = node.selected === true || node.hasAttribute('selected');
      return inertText('kabba-inert-option', (chosen ? '◉ ' : '○ ') + label.replace(/\s+/g, ' ').trim());
    }
    if (tag === 'textarea') {
      return node.textContent ? inertText('kabba-inert-textarea', node.textContent) : null;
    }
    if (tag === 'img') {
      var src = (node.getAttribute('src') || '').trim().toLowerCase();
      if (src.indexOf('data:image/') !== 0) {
        var alt = (node.getAttribute('alt') || '').trim();
        return inertText('kabba-inert-placeholder', alt ? '[Image not shown on this phone: ' + alt + ']' : IMAGE_NOT_SHOWN);
      }
    }

    var inert = INERT[tag];
    var el;
    try {
      el = document.createElement(inert || tag);
    } catch (e) {
      el = document.createElement('span'); // a tag name HTML can't create: keep its content
    }
    copySafeAttributes(node, el);
    if (inert) { el.classList.add('kabba-inert-' + tag); }
    if (tag === 'optgroup' && node.getAttribute('label')) { el.appendChild(inertText('kabba-inert-optgroup-label', node.getAttribute('label'))); }
    rebuildChildren(node, el);
    if (tag === 'object') { el.appendChild(inertText('kabba-inert-placeholder', EMBED_NOT_SHOWN)); }
    return el;
  }

  function sanitize(html) {
    var doc = new DOMParser().parseFromString('<!DOCTYPE html><html><body>' + html + '</body></html>', 'text/html');
    return rebuildChildren(doc.body, document.createDocumentFragment());
  }

  // Every page control is found BEFORE the agreement is inserted: an id in the agreement's own
  // content can never capture one.
  var content = document.getElementById('terms-dynamic-content');
  var form = document.getElementById('customer-order-sign-form');
  var submitButton = document.getElementById('submit-button');
  var formMessage = document.getElementById('form-message');
  var modal = document.getElementById('modal');
  var canvas = document.getElementById('signature-pad');
  var padMessage = document.getElementById('pad-message');
  var closeModalButton = document.getElementById('close-modal');
  var clearButton = document.getElementById('clear-signature');
  var undoButton = document.getElementById('undo-signature');
  var saveButton = document.getElementById('save-signature');
  var markerToken = String(payload.marker_token || '');
  var pad = null;
  var signature = null;
  var submitting = false;

  function show(el, text) { el.textContent = text; el.hidden = false; }
  function hide(el) { el.textContent = ''; el.hidden = true; }

  // ── The agreement, inert ──────────────────────────────────────────────
  content.appendChild(sanitize(String(payload.body || '')));

  function approvalControl() {
    var label = document.createElement('label');
    label.className = 'approval';
    var box = document.createElement('input');
    box.type = 'checkbox';
    box.className = 'customer_initials_checkbox';
    box.name = 'customer_approval[]';
    box.setAttribute('data-kabba-control', '');
    var text = document.createElement('span');
    text.textContent = 'Customer Approval Required';
    box.addEventListener('change', function () {
      label.classList.toggle('approved', box.checked);
      text.textContent = box.checked ? 'Customer Approved' : 'Customer Approval Required';
      hide(formMessage);
    });
    label.appendChild(box);
    label.appendChild(text);
    return label;
  }

  var preview = document.createElement('div');
  var previewImage = document.createElement('img');
  var clearPreview = document.createElement('button');
  var openButton = document.createElement('button');

  function signControl() {
    var block = document.createElement('div');
    block.className = 'sign-block';
    preview.className = 'signature-preview';
    preview.hidden = true;
    previewImage.alt = 'Signature Preview';
    clearPreview.type = 'button';
    clearPreview.setAttribute('data-kabba-control', '');
    clearPreview.className = 'close';
    clearPreview.setAttribute('aria-label', 'Remove signature');
    clearPreview.textContent = '×';
    preview.appendChild(previewImage);
    preview.appendChild(clearPreview);
    openButton.type = 'button';
    openButton.setAttribute('data-kabba-control', '');
    openButton.id = 'open-signature-btn';
    openButton.className = 'yellow';
    openButton.textContent = 'CLICK HERE TO SIGN';
    block.appendChild(preview);
    block.appendChild(openButton);
    return block;
  }

  // Only the renderer's markers (this load's random token) become controls; a marker typed
  // into the agreement's own content is dropped.
  function isOurs(marker, attribute) { return markerToken !== '' && marker.getAttribute(attribute) === markerToken; }
  each(content.querySelectorAll('[data-kabba-approval]'), function (marker) {
    if (isOurs(marker, 'data-kabba-approval')) { marker.replaceWith(approvalControl()); } else { marker.remove(); }
  });
  var signMarkers = Array.prototype.filter.call(content.querySelectorAll('[data-kabba-sign]'), function (marker) {
    if (isOurs(marker, 'data-kabba-sign')) { return true; }
    marker.remove();
    return false;
  });
  if (signMarkers.length === 0) {
    content.appendChild(signControl()); // an agreement of addenda only still needs a place to sign
  } else {
    signMarkers[0].replaceWith(signControl());
    each(signMarkers.slice(1), function (extra) { extra.remove(); });
  }

  // No navigation from the agreement, ever (a second wall: the rebuild leaves no link). The app's
  // own controls are never cancelled, so an approval that sat inside a link still ticks.
  document.addEventListener('click', function (event) {
    var target = event.target && event.target.closest ? event.target : null;
    if (target && target.closest('a, area') && !target.closest('[data-kabba-control], label.approval')) { event.preventDefault(); }
  }, true);

  // ── Signature pad ────────────────────────────────────────────────────
  // At most ratio 3 (a 4x display or zoom draws at 3), so even a noisy, incompressible signature
  // fits the shared size limit (TermsSignatureImage.maxPadRatio; Laravel's SignatureImage).
  var MAX_PAD_RATIO = 3;

  function sizeCanvas() {
    var ratio = Math.min(Math.max(window.devicePixelRatio || 1, 1), MAX_PAD_RATIO);
    var data = pad ? pad.toData() : null;
    canvas.width = canvas.offsetWidth * ratio;
    canvas.height = canvas.offsetHeight * ratio;
    canvas.getContext('2d').scale(ratio, ratio);
    if (pad) { pad.clear(); if (data) { pad.fromData(data); } }
  }

  function openModal() {
    modal.hidden = false;
    hide(padMessage);
    if (!pad) {
      sizeCanvas();
      pad = new window.SignaturePad(canvas, { backgroundColor: 'rgba(255,255,255,1)', penColor: 'rgb(0,0,0)' });
      window.addEventListener('resize', sizeCanvas);
    } else {
      sizeCanvas();
      pad.clear();
    }
  }

  function closeModal() {
    modal.hidden = true;
    if (pad) { pad.clear(); }
  }

  openButton.addEventListener('click', openModal);
  closeModalButton.addEventListener('click', closeModal);
  clearButton.addEventListener('click', function () { if (pad) { pad.clear(); } });
  undoButton.addEventListener('click', function () {
    if (pad && !pad.isEmpty()) { var data = pad.toData(); data.pop(); pad.fromData(data); }
  });
  saveButton.addEventListener('click', function () {
    if (!pad || pad.isEmpty()) { show(padMessage, 'Please draw your signature before saving.'); return; }
    signature = pad.toDataURL('image/png');
    previewImage.src = signature;
    preview.hidden = false;
    openButton.hidden = true;
    hide(formMessage);
    closeModal();
  });
  clearPreview.addEventListener('click', function () {
    signature = null;
    previewImage.removeAttribute('src');
    preview.hidden = true;
    openButton.hidden = false;
  });

  // ── Submit: once, to the app (which records it durably) ───────────────
  form.addEventListener('submit', function (event) {
    event.preventDefault();
    if (submitting) { return; }
    var boxes = content.querySelectorAll('input.customer_initials_checkbox');
    var unchecked = Array.prototype.filter.call(boxes, function (box) { return !box.checked; });
    if (unchecked.length > 0) { show(formMessage, 'Please provide your approvals.'); unchecked[0].scrollIntoView(); return; }
    if (boxes.length !== Number(payload.approvals_required || 0)) { show(formMessage, 'Unable to verify these terms.'); return; }
    if (!signature) { show(formMessage, 'Signature is required.'); return; }
    submitting = true;
    submitButton.disabled = true;
    window.webkit.messageHandlers.kabbaTermsSigned.postMessage({
      signature: signature,
      approvals_confirmed: boxes.length,
      identity: String(payload.identity || '')
    });
  });

  // The app calls this when it could not record the signature on the phone.
  window.kabbaTermsReset = function (message) {
    submitting = false;
    submitButton.disabled = false;
    if (message) { show(formMessage, String(message)); }
  };

  // Read-only handle for the app's own tests (content scripts can never run here).
  window.kabbaTerms = { get pad() { return pad; } };
})();
