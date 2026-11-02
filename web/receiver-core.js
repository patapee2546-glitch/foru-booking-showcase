(function (root) {
  'use strict';

  const BOOKING_SLOTS = Object.freeze(root.DEMO_CONFIG?.SLOTS || []);

  function bookingSlotsForDate(date) {
    const weekday = new Date(`${date}T12:00:00`).getDay();
    return BOOKING_SLOTS.filter(slot => !slot.days || slot.days.includes(weekday));
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function createReceiverState(input) {
    const source = input || {};
    const availability = clone(source.availability || {});
    (source.slots || []).forEach(slot => {
      availability[slotKey(slot.slot_date, String(slot.start_time || '').slice(0, 5))] = slot.is_open === true;
    });
    return {
      view: source.view || 'calendar',
      selectedDate: source.selectedDate || null,
      month: Number.isInteger(source.month) ? source.month : 7,
      year: Number.isInteger(source.year) ? source.year : 2026,
      defaultOpen: source.defaultOpen !== undefined ? Boolean(source.defaultOpen) : !Array.isArray(source.slots),
      availability,
      bookings: clone(source.bookings || []).map(booking => ({
        ...booking,
        date: booking.date || booking.slot_date,
        slot: booking.slot || String(booking.start_time || '').slice(0, 5),
        name: booking.name || booking.customer_name,
        phone: booking.phone || booking.customer_phone,
        paidAt: booking.paidAt || booking.paid_at,
        createdAt: booking.createdAt || booking.created_at,
        expiresAt: booking.expiresAt || booking.expires_at,
        removalService: booking.removalService || booking.removal_service,
        slipPath: booking.slipPath || booking.slip_path,
        slipUploadedAt: booking.slipUploadedAt || booking.slip_uploaded_at,
        designImagePath: booking.designImagePath || booking.design_image_path,
        cancelledAt: booking.cancelledAt || booking.cancelled_at,
        cancelledByRole: booking.cancelledByRole || booking.cancelled_by_role,
        refundStatus: booking.refundStatus || booking.refund_status,
      })),
    };
  }

  function selectDate(state, date) {
    const next = clone(state);
    next.selectedDate = date;
    next.view = 'day';
    return next;
  }

  function slotKey(date, start) {
    return `${date}|${start}`;
  }

  function findBooking(state, date, start) {
    return state.bookings.find(item => item.date === date && item.slot === start && ['pending', 'approved'].includes(item.status) && isActiveBooking(item));
  }

  function pendingExpiryTime(booking) {
    const explicit = new Date(booking?.expiresAt).getTime();
    if (Number.isFinite(explicit)) return explicit;
    const created = new Date(booking?.createdAt).getTime();
    return Number.isFinite(created) ? created + 5 * 60 * 1000 : NaN;
  }

  function isActiveBooking(booking, nowMs) {
    if (booking?.status !== 'pending') return true;
    const expiry = pendingExpiryTime(booking);
    return !Number.isFinite(expiry) || expiry > (nowMs ?? Date.now());
  }

  function pendingRemainingLabel(booking, nowMs) {
    const expiry = pendingExpiryTime(booking);
    const remaining = Number.isFinite(expiry) ? Math.max(0, expiry - (nowMs ?? Date.now())) : 0;
    const minutes = Math.floor(remaining / 60000);
    const seconds = Math.floor((remaining % 60000) / 1000);
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }

  function toggleSlot(state, date, start) {
    if (findBooking(state, date, start)) throw new Error('Cannot toggle a booked slot');
    const next = clone(state);
    const key = slotKey(date, start);
    next.availability[key] = next.availability[key] === false;
    return next;
  }

  function getDaySlots(state, date) {
    return bookingSlotsForDate(date).map(slot => {
      const booking = findBooking(state, date, slot.start);
      return {
        ...slot,
        status: booking ? booking.status : (
          state.availability[slotKey(date, slot.start)] === true ||
          (state.availability[slotKey(date, slot.start)] === undefined && state.defaultOpen)
            ? 'open' : 'closed'
        ),
        customer: booking ? clone(booking) : null,
      };
    });
  }

  function getMerchantCardPresentation(booking) {
    const hasSlip = Boolean(String(booking?.slipPath || '').trim());
    return {
      hasSlip,
      slipLabel: hasSlip ? 'แนบสลิปแล้ว' : 'ยังไม่แนบสลิป',
      canDeleteHistory: booking?.status === 'cancelled',
    };
  }

  function lineNotificationPresentation(bookingId, notifications) {
    const rows = (notifications || []).filter(item => String(item.booking_id) === String(bookingId));
    const byType = type => rows.find(item => item.notification_type === type);
    const confirmation = byType('booking_confirmed');
    const reminder = byType('appointment_reminder');
    const statusLabel = (row, pendingLabel) => {
      if (!row) return pendingLabel;
      return ({
        pending: 'รอส่ง',
        processing: 'กำลังส่ง',
        sent: 'ส่งแล้ว',
        failed: 'ส่งไม่สำเร็จ',
        cancelled: 'ยกเลิกการส่ง',
      })[row.status] || 'รอส่ง';
    };
    return {
      linked: rows.length > 0,
      confirmation: confirmation ? ({
        pending: 'รอส่งคำยืนยัน',
        processing: 'กำลังส่งคำยืนยัน',
        sent: 'ส่งยืนยันแล้ว',
        failed: 'ส่งยืนยันไม่สำเร็จ',
        cancelled: 'ยกเลิกการส่งคำยืนยัน',
      })[confirmation.status] || 'รอส่งคำยืนยัน' : 'ยังไม่มีงานยืนยัน',
      reminder: `เตือนก่อนนัด: ${statusLabel(reminder, 'รอส่ง')}`,
    };
  }

  root.ReceiverCore = { BOOKING_SLOTS, bookingSlotsForDate, createReceiverState, selectDate, toggleSlot, getDaySlots, getMerchantCardPresentation, lineNotificationPresentation, isActiveBooking, pendingRemainingLabel };
})(typeof globalThis !== 'undefined' ? globalThis : this);
