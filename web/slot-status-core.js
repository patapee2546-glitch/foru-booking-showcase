(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.SlotStatusCore = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  function forCustomer(input) {
    const state = input || {};
    if (state.ownApproved) {
      return { label:'ชำระแล้ว', className:'paid', bookable:false };
    }
    if (state.isBooked) return { label:'เต็ม', className:'paid', bookable:false };
    if (state.isHeld) {
      const left = holdCountdown(state.holdUntil, state.now);
      return { label:left ? `มีคนกำลังชำระเงิน ${left}` : 'กำลังชำระเงิน', className:'waiting', bookable:false };
    }
    if (state.isOpen) return { label:'ว่าง', className:'', bookable:true };
    return { label:'ปิดรับ', className:'closed', bookable:false };
  }

  // "m:ss" left on a payment hold, or '' when there is no future hold.
  function holdCountdown(holdUntil, now) {
    const ms = new Date(holdUntil).getTime() - (now ?? Date.now());
    if (!Number.isFinite(ms) || ms <= 0) return '';
    const seconds = Math.ceil(ms / 1000);
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
  }

  function summarizeDay(slots) {
    const rows = Array.isArray(slots) ? slots : [];
    const openedCount = rows.filter(slot => slot?.isOpen || slot?.isBooked || slot?.isHeld).length;
    const bookedCount = rows.filter(slot => slot?.isBooked).length;
    return {
      openedCount,
      bookedCount,
      isFull: openedCount > 0 && bookedCount === openedCount,
    };
  }

  return { forCustomer, summarizeDay, holdCountdown };
});
