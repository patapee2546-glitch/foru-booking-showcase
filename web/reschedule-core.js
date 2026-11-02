(function (root) {
  'use strict';

  const BANGKOK_OFFSET_MS = 7 * 60 * 60 * 1000;

  function appointmentMs(booking) {
    const date = String(booking?.slotDate || booking?.slot_date || booking?.date || '');
    const time = String(booking?.startTime || booking?.start_time || booking?.time || '').slice(0, 5);
    const [year, month, day] = date.split('-').map(Number);
    const [hour, minute] = time.split(':').map(Number);
    if (![year, month, day, hour, minute].every(Number.isFinite)) return NaN;
    return Date.UTC(year, month - 1, day, hour, minute) - BANGKOK_OFFSET_MS;
  }

  function rescheduleDeadline(booking) {
    const date = String(booking?.slotDate || booking?.slot_date || booking?.date || '');
    const [year, month, day] = date.split('-').map(Number);
    if (![year, month, day].every(Number.isFinite)) return NaN;
    return Date.UTC(year, month - 1, day) - BANGKOK_OFFSET_MS;
  }

  function canReschedule(booking, nowMs = Date.now()) {
    const deadline = rescheduleDeadline(booking);
    return booking?.status === 'approved' && Number.isFinite(deadline) && nowMs < deadline;
  }

  function remainingLabel(expiresAt, nowMs = Date.now()) {
    const expiry = new Date(expiresAt).getTime();
    const remaining = Number.isFinite(expiry) ? Math.max(0, expiry - nowMs) : 0;
    const minutes = Math.floor(remaining / 60000);
    const seconds = Math.floor((remaining % 60000) / 1000);
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }

  function customerAction(booking, nowMs = Date.now()) {
    return canReschedule(booking, nowMs)
      ? { enabled:true, label:'เลื่อนคิว', reason:'' }
      : { enabled:false, label:'ไม่สามารถเลื่อนได้', reason:'ต้องเลื่อนก่อนวันนัด' };
  }

  function requestStatusLabel(status) {
    return ({
      awaiting_slip:'รอชำระค่าเลื่อน',
      pending_review:'รอตรวจสอบการเลื่อนคิว',
      approved:'เลื่อนคิวแล้ว',
      rejected:'ไม่อนุมัติการเลื่อนคิว',
      expired:'คำขอหมดเวลา',
      cancelled:'ยกเลิกคำขอแล้ว',
    })[status] || status || '';
  }

  root.RescheduleCore = { appointmentMs, rescheduleDeadline, canReschedule, remainingLabel, customerAction, requestStatusLabel };
})(typeof globalThis !== 'undefined' ? globalThis : this);
