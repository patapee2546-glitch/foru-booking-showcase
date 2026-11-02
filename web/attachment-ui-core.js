(function (root, factory) {
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.AttachmentUiCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function (root) {
  'use strict';

  function formatThaiTimestamp(value) {
    if (!value) return '—';
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) return '—';
    const parts = new Intl.DateTimeFormat('th-TH', {
      timeZone:'Asia/Bangkok', day:'numeric', month:'short', year:'numeric',
      hour:'2-digit', minute:'2-digit', hourCycle:'h23'
    }).formatToParts(date).reduce((result, part) => {
      if (part.type !== 'literal') result[part.type] = part.value;
      return result;
    }, {});
    return `${parts.day} ${parts.month} ${parts.year} เวลา ${parts.hour}:${parts.minute} น.`;
  }

  function imageFilename(kind, id, mimeType) {
    const sourceType = String(mimeType || '').toLowerCase();
    const extension = ({
      'image/jpeg':'jpg', 'image/png':'png', 'image/webp':'webp'
    })[sourceType] || (/\.(png|webp|jpe?g)(?:$|\?)/.exec(sourceType)?.[1] || 'jpg').replace('jpeg', 'jpg');
    const safeKind = String(kind || 'image').toLowerCase().replace(/[^a-z0-9-]+/g, '-') || 'image';
    const safeId = String(id || 'image').replace(/[^a-zA-Z0-9-]+/g, '-') || 'image';
    return `demo-${safeKind}-${safeId}.${extension}`;
  }

  function refreshPendingStatuses(container, bookings, formatRemaining) {
    if (!container || typeof container.querySelectorAll !== 'function') return;
    const bookingById = new Map((bookings || []).map(booking => [String(booking.id), booking]));
    container.querySelectorAll('[data-customer-pending-status]').forEach(node => {
      const booking = bookingById.get(String(node.dataset.customerPendingStatus));
      if (!booking || booking.status !== 'pending') return;
      node.textContent = `รอโอนมัดจำ ${formatRemaining(booking)}`;
    });
  }

  function defaultClickDownload(url, filename) {
    const anchor = root.document.createElement('a');
    anchor.href = url;
    anchor.download = filename;
    anchor.rel = 'noopener';
    anchor.style.display = 'none';
    root.document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }

  async function downloadImage(url, filename, adapters) {
    const tools = adapters || {};
    const fetchImage = tools.fetch || root.fetch.bind(root);
    const createObjectURL = tools.createObjectURL || root.URL.createObjectURL.bind(root.URL);
    const revokeObjectURL = tools.revokeObjectURL || root.URL.revokeObjectURL.bind(root.URL);
    const clickDownload = tools.clickDownload || defaultClickDownload;
    const response = await fetchImage(url);
    if (!response.ok) throw new Error('บันทึกรูปไม่สำเร็จ กรุณาลองใหม่');
    const blob = await response.blob();
    const objectUrl = createObjectURL(blob);
    try {
      clickDownload(objectUrl, filename);
      return filename;
    } finally {
      revokeObjectURL(objectUrl);
    }
  }

  return { formatThaiTimestamp, imageFilename, refreshPendingStatuses, downloadImage };
});
