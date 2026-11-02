(function (root) {
  'use strict';

  let client = null;
  let configured = false;

  const periodEnds = Object.fromEntries((root.DEMO_CONFIG?.SLOTS || []).map(slot => [slot.start, slot.end]));

  function appError(code, detail) {
    const copy = {
      SETUP_REQUIRED: 'ยังไม่ได้ตั้งค่าระบบออนไลน์',
      AUTH_REQUIRED: 'กรุณาเข้าสู่ระบบใหม่',
      OWNER_REQUIRED: 'บัญชีนี้ไม่มีสิทธิ์เจ้าของร้าน',
      INVALID_PHONE: 'กรุณากรอกเบอร์โทรศัพท์ให้ถูกต้อง 9–10 หลัก',
      INVALID_REMOVAL: 'กรุณาเลือกบริการถอดเล็บ',
      INVALID_SLIP: 'กรุณาอัปโหลดรูปสลิป JPG, PNG หรือ WebP ขนาดไม่เกิน 5 MB',
      INVALID_SLIP_PATH: 'ไม่พบสลิปที่ต้องการ',
      INVALID_DESIGN_IMAGE: 'กรุณาแนบรูปแบบเล็บ JPG, PNG หรือ WebP ขนาดไม่เกิน 5 MB',
      UPLOAD_FAILED: 'อัปโหลดสลิปไม่สำเร็จ กรุณาลองใหม่',
      REQUEST_FAILED: 'เชื่อมต่อไม่สำเร็จ กรุณาลองใหม่',
      SLOT_CLOSED: 'รอบนี้ปิดรับหรือถูกจองแล้ว',
      LINE_FRIEND_REQUIRED: 'กรุณาเพิ่มเพื่อน LINE Official Account ของร้านก่อนจอง'
    };
    const error = new Error(copy[code] || copy.REQUEST_FAILED);
    error.code = code;
    error.detail = detail || null;
    return error;
  }

  function cleanTime(value) { return String(value || '').slice(0, 5); }
  function isValidPhone(value) { return /^\d{9,10}$/.test(String(value || '').replace(/\D/g, '')); }
  function isValidRemovalService(value) { return /^[a-z0-9_-]{1,40}$/.test(String(value || '')); }
  function sqlTime(value) { return `${cleanTime(value)}:00`; }
  function normalizeSlot(row) { return { ...row, start_time:cleanTime(row.start_time), end_time:cleanTime(row.end_time) }; }
  function normalizeBooking(row) {
    return { ...row, start_time:cleanTime(row.start_time), design_image_path:row.design_image_path || null };
  }
  function normalizeReschedule(row) {
    return {
      ...row,
      old_start_time:cleanTime(row.old_start_time),
      new_start_time:cleanTime(row.new_start_time)
    };
  }
  function validConfig(url, key) {
    return /^https:\/\/.+\.supabase\.co$/.test(url || '') && /^sb_publishable_/.test(key || '') && !/YOUR_PROJECT|REPLACE_ME/.test(`${url}${key}`);
  }
  function requireClient() { if (!configured || !client) throw appError('SETUP_REQUIRED'); return client; }
  async function value(promise, fallbackCode) {
    const { data, error } = await promise;
    if (error) throw appError(fallbackCode || 'REQUEST_FAILED', { code:error.code, message:error.message });
    return data;
  }
  async function currentUser() {
    const data = await value(requireClient().auth.getSession(), 'AUTH_REQUIRED');
    const user = data?.session?.user;
    if (!user) throw appError('AUTH_REQUIRED');
    return user;
  }

  // "remember me": owner session lives in localStorage, otherwise in sessionStorage (gone when the browser closes)
  const remembered = () => { try { return root.localStorage.getItem('demo-remember') !== '0'; } catch (_) { return true; } };
  const authStorage = {
    getItem(k) { try { return root.localStorage.getItem(k) ?? root.sessionStorage.getItem(k); } catch (_) { return null; } },
    setItem(k, v) { try { const [keep, drop] = remembered() ? [root.localStorage, root.sessionStorage] : [root.sessionStorage, root.localStorage]; keep.setItem(k, v); drop.removeItem(k); } catch (_) {} },
    removeItem(k) { try { root.localStorage.removeItem(k); root.sessionStorage.removeItem(k); } catch (_) {} },
  };
  function setOwnerRemember(on) { try { root.localStorage.setItem('demo-remember', on ? '1' : '0'); } catch (_) {} }

  function configure(options) {
    const config = options || {};
    const url = config.url || '';
    const key = config.publishableKey || '';
    const pagePath = String(root.location?.pathname || '');
    const storageKey = config.storageKey || (/\/merchant\.html$/.test(pagePath) ? 'demo-merchant-auth' : 'demo-customer-auth');
    configured = validConfig(url, key) || Boolean(config.client);
    client = config.client || (configured && root.supabase?.createClient
      ? root.supabase.createClient(url, key, { auth:{ storageKey, storage:authStorage } })
      : null);
  }

  function isConfigured() { return configured && Boolean(client); }

  async function ensureCustomerSession() {
    const auth = requireClient().auth;
    const sessionData = await value(auth.getSession(), 'AUTH_REQUIRED');
    let user = sessionData?.session?.user;
    if (!user) {
      const signIn = await value(auth.signInAnonymously(), 'AUTH_REQUIRED');
      user = signIn?.user || signIn?.session?.user;
    }
    if (!user) throw appError('AUTH_REQUIRED');
    return { userId:user.id, user };
  }

  async function ownerSignIn(email, password) {
    const data = await value(requireClient().auth.signInWithPassword({ email, password }), 'AUTH_REQUIRED');
    const user = data?.user || data?.session?.user;
    if (user?.app_metadata?.role !== 'owner') {
      await requireClient().auth.signOut();
      throw appError('OWNER_REQUIRED');
    }
    return { userId:user.id, user };
  }

  async function ownerSession() {
    const data = await value(requireClient().auth.getSession(), 'AUTH_REQUIRED');
    const user = data?.session?.user;
    return user?.app_metadata?.role === 'owner' ? { userId:user.id, user } : null;
  }

  async function ownerSignOut() { await value(requireClient().auth.signOut(), 'REQUEST_FAILED'); }

  async function listSlots(from, to) {
    const query = requireClient().from('demo_slots').select('*').gte('slot_date', from).lte('slot_date', to).order('slot_date').order('start_time');
    return (await value(query)).map(normalizeSlot);
  }

  async function listHolidays(from, to) {
    return value(requireClient().from('demo_holidays').select('day').gte('day', from).lte('day', to));
  }

  async function setHoliday(day, closed) {
    return value(requireClient().rpc('demo_set_holiday', { p_day:day, p_closed:Boolean(closed) }));
  }

  async function listMyBookings() {
    const user = await currentUser();
    const query = requireClient().from('demo_bookings').select('*').eq('customer_id', user.id).order('created_at', { ascending:false });
    return (await value(query)).map(normalizeBooking);
  }

  async function listMerchantBookings(from, to) {
    const query = requireClient().from('demo_bookings').select('*').gte('slot_date', from).lte('slot_date', to).order('slot_date').order('start_time');
    return (await value(query)).map(normalizeBooking);
  }

  async function listMerchantLineNotifications(from, to) {
    const columns = 'id,booking_id,notification_type,scheduled_for,status,attempt_count,last_error,sent_at,demo_bookings!inner(slot_date)';
    const query = requireClient().from('demo_line_notifications').select(columns)
      .gte('demo_bookings.slot_date', from).lte('demo_bookings.slot_date', to)
      .order('scheduled_for', { ascending:true });
    const { data, error } = await query;
    if (error?.code === 'PGRST205') return [];
    if (error) throw appError('REQUEST_FAILED', { code:error.code, message:error.message });
    return data || [];
  }

  async function listMyRescheduleRequests() {
    const user = await currentUser();
    const query = requireClient().from('demo_reschedule_requests').select('*').eq('customer_id', user.id).order('created_at', { ascending:false });
    return (await value(query)).map(normalizeReschedule);
  }

  async function listMerchantRescheduleRequests(from, to) {
    const query = requireClient().from('demo_reschedule_requests').select('*').gte('old_slot_date', from).lte('old_slot_date', to).order('created_at', { ascending:false });
    return (await value(query)).map(normalizeReschedule);
  }

  // where the customer came from: ?ref=ig on the booking link, kept 30 days on this device (LINE login redirects drop the query)
  const REF_KEY='demo-ref';
  try { const r=new URLSearchParams(location.search).get('ref'); if (r && /^[a-z0-9_-]{1,30}$/i.test(r)) localStorage.setItem(REF_KEY, JSON.stringify({ r:r.toLowerCase(), t:Date.now() })); } catch (_) {}
  function refSource() { try { const v=JSON.parse(localStorage.getItem(REF_KEY)); return v && Date.now()-v.t < 30*864e5 ? v.r : null; } catch (_) { return null; } }

  async function createPendingBooking(input) {
    if (!isValidPhone(input.phone)) throw appError('INVALID_PHONE');
    if (!isValidRemovalService(input.removalService)) throw appError('INVALID_REMOVAL');
    if (!String(input.lineAccessToken || '').trim()) throw appError('LINE_FRIEND_REQUIRED');
    await currentUser();
    const payload = {
      id:input.id,
      date:input.date,
      start:cleanTime(input.start),
      name:String(input.name || '').trim(),
      phone:String(input.phone || '').replace(/\D/g, ''),
      removalService:input.removalService,
      designImagePath:input.designImagePath || null,
      lineAccessToken:String(input.lineAccessToken).trim(),
      benefit:input.benefit || null,
      source:refSource()
    };
    const data = await invokeWithMessage('create-booking',payload);
    return normalizeBooking(data);
  }

  async function linkLineCustomer(idToken, accessToken) {
    await currentUser();
    const data = await value(requireClient().functions.invoke('link-line-customer', {
      body:{ idToken:String(idToken || ''), accessToken:String(accessToken || '') }
    }), 'LINE_FRIEND_REQUIRED');
    return data;
  }

  async function invokeWithMessage(name,body){
    const {data,error}=await requireClient().functions.invoke(name,{body});
    if(error){
      let message='';try{message=(await error.context?.json())?.message||'';}catch(_){}
      const copy={PROMO_FULL:'สิทธิ์เต็มแล้วค่ะ',PROMO_CLOSED:'ยังไม่เปิดโปรหรือปิดรับแล้ว',PROMO_EXPIRED:'สิทธิ์หมดเวลาหรือใช้จองแล้ว',PROMO_SLOT:'รอบนี้ไม่ร่วมโปรวงล้อ',PROMO_CODE:'รหัสไม่ถูกต้อง หมดอายุ หรือถูกยกเลิก',PROMO_SELF:'ใช้รหัสแนะนำตัวเองไม่ได้',PROMO_CODE_USED:'รหัสนี้มีผู้ใช้สิทธิ์แล้ว',PROMO_NEW_ONLY:'โปรเพื่อนสำหรับลูกค้าใหม่เท่านั้น',PROMO_CREDIT:'เครดิตไม่พร้อมใช้หรือหมดอายุ',PROMO_CREDIT_USED:'เครดิตถูกใช้จองคิวอื่นแล้ว',PROMO_NOT_APPROVED:'คิวนี้ยังไม่ยืนยันหรือถูกยกเลิก',PROMO_ALREADY_USED:'สิทธิ์นี้ถูกใช้หรือปิดยอดแล้ว จึงยกเลิกไม่ได้',PROMO_ALREADY_SETTLED:'บันทึกยอดชำระครบแล้ว ไม่สามารถแก้ยอดซ้ำ',PROMO_SLOTS:'กรุณาเลือกรอบว่างในอนาคตที่ไม่ซ้ำกัน',OWNER_REQUIRED:'กรุณาเข้าสู่ระบบเจ้าของร้าน',LINE_FRIEND_REQUIRED:'กรุณาเพิ่มเพื่อนและเชื่อม LINE ก่อน',INVALID_AMOUNT:'กรุณากรอกยอดเงินที่ถูกต้อง',slot_closed:'รอบนี้ถูกจองหรือปิดรับแล้ว'};
      const failure=new Error(copy[message]||'ดำเนินการไม่สำเร็จ กรุณารีเฟรชแล้วลองใหม่');
      failure.code=message;
      throw failure;
    }
    return data;
  }
  async function promotion(action,data={}) {
    await currentUser();
    try { return await invokeWithMessage('promotion',{action,data}); }
    catch(error) {
      // A LINE link can move to another browser session. Re-verify the current
      // browser's LINE credentials on the server before retrying once.
      if(error.code!=='LINE_FRIEND_REQUIRED'||!root.liff?.isLoggedIn?.())throw error;
      const idToken=root.liff.getIDToken?.(),accessToken=root.liff.getAccessToken?.();
      if(!idToken||!accessToken)throw error;
      await linkLineCustomer(idToken,accessToken);
      return invokeWithMessage('promotion',{action,data});
    }
  }

  // Resize big phone photos to max 1600px JPEG before upload (~150KB instead of ~600KB). Falls back to the original file.
  async function shrinkImage(file, maxSide = 1600) {
    try {
      if (typeof createImageBitmap !== 'function' || typeof document === 'undefined') return file;
      const bitmap = await createImageBitmap(file);
      const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(bitmap.width * scale);
      canvas.height = Math.round(bitmap.height * scale);
      canvas.getContext('2d').drawImage(bitmap, 0, 0, canvas.width, canvas.height);
      const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.82));
      return blob && blob.size < file.size ? new File([blob], 'image.jpg', { type:'image/jpeg' }) : file;
    } catch (_) { return file; }
  }

  async function uploadDesignImage(bookingId, file) {
    const allowedTypes = ['image/jpeg','image/png','image/webp'];
    if (!file || !allowedTypes.includes(file.type) || file.size > 5 * 1024 * 1024) throw appError('INVALID_DESIGN_IMAGE');
    const user = await currentUser();
    file = await shrinkImage(file);
    const ext = ({ 'image/jpeg':'jpg', 'image/png':'png', 'image/webp':'webp' })[file.type];
    const path = `${user.id}/${bookingId}/${crypto.randomUUID()}.${ext}`;
    await value(requireClient().storage.from('demo-design-images').upload(path, file, { contentType:file.type, upsert:false }), 'UPLOAD_FAILED');
    return path;
  }

  async function getDesignImageUrl(path) {
    if (!String(path || '').trim()) throw appError('INVALID_SLIP_PATH');
    const data = await value(requireClient().storage.from('demo-design-images').createSignedUrl(path, 300), 'REQUEST_FAILED');
    if (!data?.signedUrl) throw appError('REQUEST_FAILED');
    return data.signedUrl;
  }

  async function uploadPaymentSlip(bookingId, file) {
    const allowedTypes = ['image/jpeg','image/png','image/webp'];
    if (!file || !allowedTypes.includes(file.type) || file.size > 5 * 1024 * 1024) throw appError('INVALID_SLIP');
    const user = await currentUser();
    file = await shrinkImage(file);
    const ext = ({ 'image/jpeg':'jpg', 'image/png':'png', 'image/webp':'webp' })[file.type];
    const path = `${user.id}/${bookingId}/${crypto.randomUUID()}.${ext}`;
    await value(requireClient().storage.from('demo-payment-slips').upload(path, file, { contentType:file.type, upsert:false }), 'UPLOAD_FAILED');
    return path;
  }

  async function claimBooking(id, slipPath) {
    const data = await value(requireClient().functions.invoke('claim-booking', { body:{ bookingId:id, slipPath } }), 'REQUEST_FAILED');
    return data?.won === true;
  }

  async function cancelBooking(id) {
    return value(requireClient().functions.invoke('cancel-booking', { body:{ bookingId:id } }), 'REQUEST_FAILED');
  }

  async function deleteCancelledBooking(id) {
    return value(requireClient().functions.invoke('delete-cancelled-booking', { body:{ bookingId:id } }), 'REQUEST_FAILED');
  }

  async function getSlipUrl(path) {
    if (!String(path || '').trim()) throw appError('INVALID_SLIP_PATH');
    const data = await value(requireClient().storage.from('demo-payment-slips').createSignedUrl(path, 300), 'REQUEST_FAILED');
    if (!data?.signedUrl) throw appError('REQUEST_FAILED');
    return data.signedUrl;
  }

  async function createRescheduleRequest(bookingId, newDate, newStart) {
    return value(requireClient().functions.invoke('create-reschedule-request', {
      body:{ bookingId, newDate, newStart:cleanTime(newStart) }
    }), 'REQUEST_FAILED');
  }

  async function uploadRescheduleSlip(requestId, file) {
    const allowedTypes = ['image/jpeg','image/png','image/webp'];
    if (!file || !allowedTypes.includes(file.type) || file.size > 5 * 1024 * 1024) throw appError('INVALID_SLIP');
    const user = await currentUser();
    file = await shrinkImage(file);
    const ext = ({ 'image/jpeg':'jpg', 'image/png':'png', 'image/webp':'webp' })[file.type];
    const path = `${user.id}/${requestId}/${crypto.randomUUID()}.${ext}`;
    await value(requireClient().storage.from('demo-reschedule-slips').upload(path, file, { contentType:file.type, upsert:false }), 'UPLOAD_FAILED');
    return path;
  }

  async function submitRescheduleSlip(requestId, slipPath) {
    return value(requireClient().functions.invoke('submit-reschedule-slip', { body:{ requestId, slipPath } }), 'REQUEST_FAILED');
  }

  async function reviewRescheduleRequest(requestId, approve) {
    return value(requireClient().functions.invoke('review-reschedule-request', { body:{ requestId, decision:approve ? 'approve' : 'reject' } }), 'REQUEST_FAILED');
  }

  async function cancelRescheduleRequest(requestId) {
    return value(requireClient().functions.invoke('cancel-reschedule-request', { body:{ requestId } }), 'REQUEST_FAILED');
  }

  async function getRescheduleSlipUrl(path) {
    if (!String(path || '').trim()) throw appError('INVALID_SLIP_PATH');
    const data = await value(requireClient().storage.from('demo-reschedule-slips').createSignedUrl(path, 300), 'REQUEST_FAILED');
    if (!data?.signedUrl) throw appError('REQUEST_FAILED');
    return data.signedUrl;
  }

  async function listServices() {
    const query = requireClient().from('demo_services').select('*').order('sort').order('key');
    const { data, error } = await query;
    if (error?.code === 'PGRST205') return [];
    if (error) throw appError('REQUEST_FAILED', { code:error.code, message:error.message });
    return data || [];
  }

  async function saveService(row) {
    const payload = { key:row.key, label:String(row.label || '').trim(), price:row.price === '' || row.price == null ? null : Number(row.price), sort:Number(row.sort) || 0, active:Boolean(row.active) };
    return value(requireClient().from('demo_services').upsert(payload, { onConflict:'key' }).select('*').single(), 'REQUEST_FAILED');
  }

  async function setAttendance(bookingId, attendance) {
    return value(requireClient().rpc('demo_set_attendance', { p_booking_id:bookingId, p_attendance:attendance }), 'REQUEST_FAILED');
  }

  async function setSlotOpen(date, start, isOpen) {
    const user = await currentUser();
    const end = periodEnds[cleanTime(start)];
    if (!end) throw appError('REQUEST_FAILED');
    const payload = { slot_date:date, start_time:sqlTime(start), end_time:sqlTime(end), is_open:Boolean(isOpen), updated_by:user.id, updated_at:new Date().toISOString() };
    const query = requireClient().from('demo_slots').upsert(payload, { onConflict:'slot_date,start_time' }).select('*').single();
    return normalizeSlot(await value(query));
  }

  async function verifyPayment(bookingId, ok) {
    return value(requireClient().rpc('demo_verify_payment', { p_booking_id:bookingId, p_ok:Boolean(ok) }), 'REQUEST_FAILED');
  }

  async function listSettlements(bookingIds) {
    if (!bookingIds.length) return [];
    const { data, error } = await requireClient().from('demo_service_settlements').select('booking_id,subtotal,discount,deposit,amount_due').in('booking_id', bookingIds);
    if (error) return [];
    return data || [];
  }

  async function listBroadcasts() {
    const { data, error } = await requireClient().from('demo_promo_broadcasts').select('*').order('send_at', { ascending:false }).limit(20);
    if (error) return [];
    return data || [];
  }

  async function createBroadcast(message, sendAt) {
    return value(requireClient().from('demo_promo_broadcasts').insert({ message:String(message || '').trim(), send_at:new Date(sendAt).toISOString() }).select('*').single(), 'REQUEST_FAILED');
  }

  async function cancelBroadcast(id) {
    return value(requireClient().from('demo_promo_broadcasts').update({ status:'cancelled' }).eq('id', id).eq('status', 'pending'), 'REQUEST_FAILED');
  }

  async function lineUsage() {
    const [audience, used] = await Promise.all([
      requireClient().rpc('demo_broadcast_audience_count'),
      requireClient().rpc('demo_line_messages_this_month'),
    ]);
    return { audience:audience.data ?? null, used:used.data ?? null };
  }

  async function joinWaitlist(date, start) {
    return value(requireClient().rpc('demo_join_waitlist', { p_slot_date:date, p_start_time:sqlTime(start) }), 'REQUEST_FAILED');
  }

  async function listMyWaitlist() {
    const { data, error } = await requireClient().from('demo_waitlist').select('slot_date,start_time');
    if (error) return [];
    return (data || []).map(row => `${row.slot_date}_${cleanTime(row.start_time)}`);
  }

  async function searchCustomerBookings(phoneDigits) {
    const phone = String(phoneDigits || '').replace(/\D/g, '');
    if (phone.length < 4) return [];
    const query = requireClient().from('demo_bookings').select('*').ilike('customer_phone', `%${phone}%`).order('slot_date', { ascending:false }).limit(50);
    return (await value(query)).map(normalizeBooking);
  }

  async function getCustomerNote(phone) {
    const { data } = await requireClient().from('demo_customer_notes').select('note').eq('phone', phone).maybeSingle();
    return data?.note || '';
  }

  async function saveCustomerNote(phone, note) {
    return value(requireClient().from('demo_customer_notes').upsert({ phone, note:String(note || '').slice(0, 1000), updated_at:new Date().toISOString() }, { onConflict:'phone' }), 'REQUEST_FAILED');
  }

  // Who is filling in which slot right now (Realtime presence, nothing stored). onPeers gets [{date,time,initial}] of other viewers.
  function bookingPresence(onPeers) {
    const db = requireClient();
    const key = crypto.randomUUID();
    const channel = db.channel('demo-booking-presence', { config:{ presence:{ key } } });
    channel.on('presence', { event:'sync' }, () => {
      const peers = Object.entries(channel.presenceState()).filter(([k]) => k !== key).flatMap(([, metas]) => metas).filter(meta => meta?.date && meta?.time);
      onPeers?.(peers);
    }).subscribe();
    return {
      track: data => data ? channel.track(data) : channel.untrack(),
      stop: () => db.removeChannel(channel),
    };
  }

  function subscribe(scope, onChange, onStatus) {
    const db = requireClient();
    let refreshRunning = false;
    let refreshQueued = false;
    let queuedReason = null;
    async function dispatchChange(reason) {
      queuedReason = reason;
      if (refreshRunning) {
        refreshQueued = true;
        return;
      }
      refreshRunning = true;
      try {
        do {
          refreshQueued = false;
          const currentReason = queuedReason;
          await onChange?.(currentReason);
        } while (refreshQueued);
      } finally {
        refreshRunning = false;
      }
    }
    const channel = db.channel(`demo-${scope}-${Date.now()}`)
      .on('postgres_changes', { event:'*', schema:'public', table:'demo_slots' }, () => dispatchChange('slots'))
      .on('postgres_changes', { event:'*', schema:'public', table:'demo_holidays' }, () => dispatchChange('holidays'))
      .on('postgres_changes', { event:'*', schema:'public', table:'demo_bookings' }, () => dispatchChange('bookings'))
      .on('postgres_changes', { event:'*', schema:'public', table:'demo_reschedule_requests' }, () => dispatchChange('reschedules'))
      .on('postgres_changes', { event:'*', schema:'public', table:'demo_line_notifications' }, () => dispatchChange('line-notifications'))
      .subscribe(status => onStatus?.(status));
    return () => { db.removeChannel(channel); };
  }

  root.DemoData = {
    promotion,
    configure, isConfigured, ensureCustomerSession, ownerSignIn, ownerSignOut,
    listSlots, listHolidays, setHoliday, listMyBookings, listMerchantBookings, listMerchantLineNotifications, listMyRescheduleRequests, listMerchantRescheduleRequests, createPendingBooking, linkLineCustomer,
    ownerSession, setOwnerRemember, uploadPaymentSlip, claimBooking, cancelBooking, deleteCancelledBooking, getSlipUrl, uploadDesignImage, getDesignImageUrl, setSlotOpen, setAttendance, listServices, saveService, verifyPayment, listSettlements, listBroadcasts, createBroadcast, cancelBroadcast, lineUsage, joinWaitlist, listMyWaitlist, searchCustomerBookings, getCustomerNote, saveCustomerNote, bookingPresence, subscribe,
    createRescheduleRequest, uploadRescheduleSlip, submitRescheduleSlip,
    reviewRescheduleRequest, cancelRescheduleRequest, getRescheduleSlipUrl,
    isValidPhone, isValidRemovalService,
    _normalizeSlot:normalizeSlot, _normalizeBooking:normalizeBooking, _normalizeReschedule:normalizeReschedule
  };

  const initial = root.DEMO_CONFIG || {};
  if (initial.SUPABASE_URL || initial.SUPABASE_PUBLISHABLE_KEY) {
    configure({ url:initial.SUPABASE_URL, publishableKey:initial.SUPABASE_PUBLISHABLE_KEY });
  }
})(typeof window !== 'undefined' ? window : globalThis);
