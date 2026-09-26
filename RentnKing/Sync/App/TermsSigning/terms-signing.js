// Dispatch offline Phase 5 — the local Terms & Conditions signing page.
//
// The agreement body arrives as data (window.kabbaTermsPayload.body), is parsed
// in an INERT document (DOMParser never runs scripts), stripped of anything
// active, and only then inserted. The page's Content-Security-Policy is the
// second wall: no script but the two nonce-tagged ones, no inline handlers, no
// javascript: URLs, no network, no frames. The app's own approval checkboxes
// and sign button replace the renderer's inert markers.
(function () {
  'use strict';

  var payload = window.kabbaTermsPayload || {};
  var BLOCKED = ['script', 'iframe', 'frame', 'frameset', 'object', 'embed', 'applet', 'link', 'meta', 'base',
    'form', 'input', 'button', 'select', 'textarea', 'option', 'audio', 'video', 'source', 'track', 'portal',
    'noscript', 'template', 'dialog', 'slot', 'svg', 'math'];
  var URL_ATTRIBUTES = ['href', 'src', 'srcset', 'action', 'formaction', 'xlink:href', 'data', 'poster', 'background',
    'ping', 'lowsrc', 'dynsrc', 'codebase', 'cite', 'longdesc', 'usemap', 'manifest'];
  var DROPPED_ATTRIBUTES = ['target', 'formtarget', 'contenteditable', 'autofocus', 'srcdoc'];

  function each(list, fn) { Array.prototype.slice.call(list).forEach(fn); }

  function sanitize(html) {
    var doc = new DOMParser().parseFromString('<!DOCTYPE html><html><body>' + html + '</body></html>', 'text/html');
    var body = doc.body;
    BLOCKED.forEach(function (tag) { each(body.getElementsByTagName(tag), function (el) { el.remove(); }); });
    each(body.getElementsByTagName('style'), function (el) {
      if (/@import|url\s*\(/i.test(el.textContent || '')) { el.remove(); }
    });
    each(body.querySelectorAll('*'), function (el) {
      each(el.attributes, function (attribute) {
        var name = attribute.name.toLowerCase();
        var value = (attribute.value || '').trim().toLowerCase();
        if (name.indexOf('on') === 0 || DROPPED_ATTRIBUTES.indexOf(name) !== -1) {
          el.removeAttribute(attribute.name);
        } else if (URL_ATTRIBUTES.indexOf(name) !== -1) {
          var inlineImage = el.tagName === 'IMG' && name === 'src' && value.indexOf('data:image/') === 0;
          if (!inlineImage) { el.removeAttribute(attribute.name); }
        } else if (name === 'style' && /url\s*\(|expression\s*\(/i.test(value)) {
          el.removeAttribute(attribute.name);
        }
      });
    });
    return body;
  }

  var content = document.getElementById('terms-dynamic-content');
  var form = document.getElementById('customer-order-sign-form');
  var submitButton = document.getElementById('submit-button');
  var formMessage = document.getElementById('form-message');
  var modal = document.getElementById('modal');
  var canvas = document.getElementById('signature-pad');
  var padMessage = document.getElementById('pad-message');
  var pad = null;
  var signature = null;
  var submitting = false;

  function show(el, text) { el.textContent = text; el.hidden = false; }
  function hide(el) { el.textContent = ''; el.hidden = true; }

  // ── The agreement, inert ──────────────────────────────────────────────
  var clean = sanitize(String(payload.body || ''));
  while (clean.firstChild) { content.appendChild(document.adoptNode(clean.firstChild)); }

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

  each(content.querySelectorAll('span[data-kabba-approval]'), function (marker) { marker.replaceWith(approvalControl()); });
  var signMarkers = content.querySelectorAll('span[data-kabba-sign]');
  if (signMarkers.length === 0) {
    content.appendChild(signControl()); // an agreement of addenda only still needs a place to sign
  } else {
    signMarkers[0].replaceWith(signControl());
    each(Array.prototype.slice.call(signMarkers, 1), function (extra) { extra.remove(); });
  }

  // No navigation from the agreement, ever.
  document.addEventListener('click', function (event) {
    var link = event.target && event.target.closest ? event.target.closest('a, area') : null;
    if (link) { event.preventDefault(); }
  }, true);

  // ── Signature pad ────────────────────────────────────────────────────
  function sizeCanvas() {
    var ratio = Math.max(window.devicePixelRatio || 1, 1);
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
  document.getElementById('close-modal').addEventListener('click', closeModal);
  document.getElementById('clear-signature').addEventListener('click', function () { if (pad) { pad.clear(); } });
  document.getElementById('undo-signature').addEventListener('click', function () {
    if (pad && !pad.isEmpty()) { var data = pad.toData(); data.pop(); pad.fromData(data); }
  });
  document.getElementById('save-signature').addEventListener('click', function () {
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
