import {
  classifyLineFailure,
  formatNotification,
  sendNotificationJob,
} from './line-notification.ts'
import {
  pushLineText,
  verifyLineAccess,
  verifyLineIdToken,
} from './line-messaging.ts'

function equal(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`)
}

function includes(actual: string, expected: string, label: string) {
  if (!actual.includes(expected)) throw new Error(`${label}: missing ${expected} in ${actual}`)
}

Deno.test('owner booking notification reads and includes phone without adding it to customer messages', async()=>{
 const booking={id:'b',status:'approved',customer_name:'ลูกค้า',customer_phone:'0812345678',slot_date:'2026-09-14',start_time:'10:00:00',demo_slots:{end_time:'12:30:00'}};
 const admin={from:()=>({select:(columns:string)=>({eq:()=>({maybeSingle:async()=>({data:{...booking,customer_phone:columns.split(',').includes('customer_phone')?booking.customer_phone:undefined},error:null})})})})};
 let copy='';
 await sendNotificationJob(admin,{id:'j',booking_id:'b',recipient_line_user_id:'Uowner',notification_type:'owner_booking_confirmed'},{channelAccessToken:'test'},async(_recipient,text)=>{copy=text});
 includes(copy,'ลูกค้า: ลูกค้า\nเบอร์โทร: 0812345678','phone follows name');
 for(const type of ['booking_confirmed','appointment_reminder'] as const){
  equal(formatNotification(type,{...booking,end_time:'12:30:00'}).includes('0812345678'),false,'customer copy has no phone');
 }
 includes(formatNotification('owner_booking_confirmed',{...booking,customer_phone:undefined,end_time:'12:30:00'} as any),'เบอร์โทร: ไม่ระบุ','missing phone fallback');
})

Deno.test('owner booking notice contains customer, appointment and merchant link', () => {
  const text = formatNotification('owner_booking_confirmed' as any, {
    slot_date:'2026-09-08', start_time:'10:00:00', end_time:'12:30:00', customer_name:'ทดสอบ',
  } as any)
  includes(text, 'ทดสอบ', 'customer name')
  includes(text, '8 กันยายน 2569', 'date')
  includes(text, '10:00–12:30', 'time')
  includes(text, 'https://demo-nails.example.com/merchant.html', 'merchant link')
})

Deno.test('confirmation formats the database appointment in Thai', () => {
  const text = formatNotification('booking_confirmed', {
    slot_date: '2026-09-08',
    start_time: '10:00:00',
    end_time: '12:30:00',
  })
  includes(text, '8 กันยายน 2569', 'Thai appointment date')
  includes(text, '10:00–12:30', 'appointment period')
})

Deno.test('special-slot LINE notices clearly identify the special round', () => {
  for (const type of ['owner_booking_confirmed', 'booking_confirmed'] as const) {
    const text = formatNotification(type, {
      slot_date:'2026-09-08', start_time:'10:00:00', end_time:'12:30:00', is_special:true,
    })
    includes(text, 'รอบพิเศษ', `${type} special label`)
  }
  const normal = formatNotification('booking_confirmed', {
    slot_date:'2026-09-08', start_time:'10:00:00', end_time:'12:30:00', is_special:false,
  })
  equal(normal.includes('รอบพิเศษ'), false, 'normal round has no special label')
})

Deno.test('reminder copy states that the appointment is in one hour', () => {
  const text = formatNotification('appointment_reminder', {
    slot_date: '2026-09-08',
    start_time: '17:00:00',
    end_time: '19:30:00',
  })
  includes(text, 'อีก 1 ชั่วโมง', 'one-hour reminder')
  includes(text, '17:00–19:30', 'reminder period')
})

Deno.test('LINE failure classification retries only transient responses', () => {
  equal(classifyLineFailure(408), 'retryable', 'timeout')
  equal(classifyLineFailure(429), 'retryable', 'rate limit')
  equal(classifyLineFailure(503), 'retryable', 'server error')
  equal(classifyLineFailure(400), 'permanent', 'bad recipient')
})

Deno.test('ID token verification sends token and channel ID and returns sub', async () => {
  const requests: Request[] = []
  const fakeFetch: typeof fetch = async (input, init) => {
    requests.push(new Request(input, init))
    return Response.json({ sub: 'U12345678', aud: '1234567890' })
  }
  const result = await verifyLineIdToken('id-token-value', '1234567890', fakeFetch)
  equal(result.lineUserId, 'U12345678', 'verified LINE user')
  equal(requests.length, 1, 'single verification request')
  const body = await requests[0].text()
  includes(body, 'id_token=id-token-value', 'ID token form field')
  includes(body, 'client_id=1234567890', 'channel ID form field')
})

Deno.test('friend check verifies channel and user before accepting friendFlag', async () => {
  const fakeFetch: typeof fetch = async (input) => {
    const url = String(input)
    if (url.includes('/oauth2/v2.1/verify')) return Response.json({ client_id: '1234567890', expires_in: 3600 })
    if (url.includes('/v2/profile')) return Response.json({ userId: 'U12345678', displayName: 'Customer' })
    if (url.includes('/friendship/v1/status')) return Response.json({ friendFlag: true })
    return new Response(null, { status: 404 })
  }
  const result = await verifyLineAccess('user-access-token', '1234567890', 'U12345678', fakeFetch)
  equal(result.friend, true, 'verified friend')
})

Deno.test('push message addresses the verified recipient and uses retry key', async () => {
  let request: Request | undefined
  const fakeFetch: typeof fetch = async (input, init) => {
    request = new Request(input, init)
    return new Response(null, { status: 200 })
  }
  await pushLineText('U12345678', 'ยืนยันคิวแล้ว', 'bot-token', 'job-uuid', fakeFetch)
  if (!request) throw new Error('push request was not sent')
  equal(request.headers.get('authorization'), 'Bearer bot-token', 'bot authorization')
  equal(request.headers.get('x-line-retry-key'), 'job-uuid', 'LINE retry key')
  const payload = await request.json()
  equal(payload.to, 'U12345678', 'push recipient')
  equal(payload.messages[0].text, 'ยืนยันคิวแล้ว', 'push copy')
})

Deno.test('notification job sends only an approved booking to its snapshotted recipient', async () => {
  const booking = {
    id: 'booking-1', status: 'approved', slot_date: '2026-09-08', start_time: '10:00:00',
    demo_slots: { end_time: '12:30:00' },
  }
  const admin = {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: booking, error: null }) }),
      }),
    }),
  }
  let recipient = ''
  let copy = ''
  const fakePush = async (lineUserId: string, text: string) => {
    recipient = lineUserId
    copy = text
  }
  const outcome = await sendNotificationJob(admin, {
    id: 'job-uuid', booking_id: 'booking-1', recipient_line_user_id: 'U12345678',
    notification_type: 'booking_confirmed',
  }, { channelAccessToken: 'bot-token' }, fakePush)
  equal(outcome, 'sent', 'send outcome')
  equal(recipient, 'U12345678', 'snapshotted recipient')
  includes(copy, '10:00–12:30', 'database appointment period')
})

Deno.test('owner cancellation sends cancelled status and appointment only for cancelled bookings', async () => {
  const booking = {status:'cancelled',customer_name:'ทดสอบ',slot_date:'2026-09-08',start_time:'10:00:00',demo_slots:{end_time:'12:30:00'}}
  const admin = {from:()=>({select:()=>({eq:()=>({maybeSingle:async()=>({data:booking,error:null})})})})}
  let sends=0
  const job={id:'job-cancel',booking_id:'booking-1',recipient_line_user_id:'Uowner',notification_type:'owner_booking_cancelled' as any}
  const push=async(recipient:string,text:string)=>{
    equal(recipient,'Uowner','owner recipient')
    includes(text,'ยกเลิกคิว','cancelled status')
    includes(text,'ทดสอบ','customer')
    includes(text,'8 กันยายน 2569','original date')
    includes(text,'10:00–12:30','original period')
    sends++
  }
  equal(await sendNotificationJob(admin,job,{channelAccessToken:'token'},push),'sent','cancel notice sent')
  booking.status='approved'
  equal(await sendNotificationJob(admin,job,{channelAccessToken:'token'},push),'cancelled','active booking not a cancellation')
  equal(sends,1,'one cancellation send')
})

Deno.test('notification job cancels when booking is no longer approved', async () => {
  const admin = {
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: { id:'booking-1', status:'cancelled' }, error:null }) }),
      }),
    }),
  }
  let sends = 0
  const outcome = await sendNotificationJob(admin, {
    id: 'job-uuid', booking_id: 'booking-1', recipient_line_user_id: 'U12345678',
    notification_type: 'appointment_reminder',
  }, { channelAccessToken: 'bot-token' }, async () => { sends += 1 })
  equal(outcome, 'cancelled', 'cancelled outcome')
  equal(sends, 0, 'cancelled booking is never sent')
})

Deno.test('follow-up messages: shop cancel, day reminder, review, rebook, reschedule', async () => {
  const appt = { customer_name:'ลูกค้า', slot_date:'2026-10-20', start_time:'10:00:00', end_time:'12:30:00' }
  includes(formatNotification('booking_cancelled_by_shop', appt), 'ยกเลิกคิว', 'shop cancel')
  includes(formatNotification('appointment_reminder_day', appt), 'พรุ่งนี้', 'day reminder')
  includes(formatNotification('review_request', appt, { review:'https://g.page/r/x' }), 'https://g.page/r/x', 'review link')
  includes(formatNotification('owner_booking_rescheduled', appt), 'เลื่อนคิว', 'owner reschedule')
  includes(formatNotification('owner_appointment_reminder', appt), 'อีก 1 ชม.', 'owner 1h reminder')
  includes(formatNotification('owner_slip_failed', { ...appt, slip_check_message:'สลิปซ้ำ' }), 'สลิปซ้ำ', 'owner slip failed reason')
  includes(formatNotification('rebook_nudge', appt, { booking:'https://demo.example/' }), 'https://demo.example/', 'rebook link')
  const waitlist = formatNotification('waitlist_open', appt, { booking:'https://demo.example/' })
  includes(waitlist, 'ว่างแล้ว', 'waitlist copy'); equal(waitlist.includes('ลูกค้า'), false, 'waitlist hides previous customer')
  const row = { id:'b', status:'approved', attendance:'no_show', customer_name:'ลูกค้า', slot_date:'2026-10-20', start_time:'10:00:00', demo_slots:{ end_time:'12:30:00' } }
  const admin = { from:()=>({ select:()=>({ eq:()=>({ maybeSingle:async()=>({ data:row, error:null }) }) }) }) }
  const job = { id:'j', booking_id:'b', recipient_line_user_id:'U1', notification_type:'review_request' as const }
  equal(await sendNotificationJob(admin as any, job, { channelAccessToken:'t', reviewUrl:'https://g.page/r/x' }, async()=>{}), 'cancelled', 'no-show gets no review request')
  row.attendance = 'arrived'
  equal(await sendNotificationJob(admin as any, job, { channelAccessToken:'t' }, async()=>{}), 'cancelled', 'no review url configured')
  equal(await sendNotificationJob(admin as any, job, { channelAccessToken:'t', reviewUrl:'https://g.page/r/x' }, async()=>{}), 'sent', 'review sent')
  row.status = 'cancelled'
  equal(await sendNotificationJob(admin as any, { ...job, notification_type:'booking_cancelled_by_shop' }, { channelAccessToken:'t' }, async()=>{}), 'sent', 'shop cancel needs cancelled booking')
})
