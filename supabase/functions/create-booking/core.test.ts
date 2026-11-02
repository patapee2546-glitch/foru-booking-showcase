import { createBooking, CreateBookingError } from './core.ts'

function equal(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`)
}

const validInput = {
  id: '20000000-0000-4000-8000-000000000001',
  date: '2026-09-08',
  start: '15:00',
  name: 'ลูกค้า',
  phone: '081-234-5678',
  removalService: 'gel',
  designImagePath: null,
  lineAccessToken: 'line-access-token',
}

Deno.test('verified LINE friend creates a five-minute booking through the RPC boundary', async () => {
  const calls: Array<Record<string, unknown>> = []
  const result = await createBooking(validInput, 'customer-uuid', { channelId:'1234567890' }, {
    loadLineLink: async () => ({ lineUserId:'U12345678' }),
    verifyAccess: async () => ({ friend:true }),
    insertPendingBooking: async args => {
      calls.push(args)
      return { id:args.bookingId, status:'pending', expires_at:'2026-09-08T03:05:00.000Z' }
    },
  })
  equal(result.status, 'pending', 'pending status')
  equal(calls.length, 1, 'single booking transaction')
  equal(calls[0].customerId, 'customer-uuid', 'authenticated owner')
  equal(calls[0].phone, '0812345678', 'normalized phone')
  equal(calls[0].start, '15:00:00', 'SQL time')
})

Deno.test('non-friend cannot create a booking', async () => {
  let inserts = 0
  try {
    await createBooking(validInput, 'customer-uuid', { channelId:'1234567890' }, {
      loadLineLink: async () => ({ lineUserId:'U12345678' }),
      verifyAccess: async () => ({ friend:false }),
      insertPendingBooking: async () => { inserts += 1; return {} },
    })
    throw new Error('expected friend rejection')
  } catch (error) {
    if (!(error instanceof CreateBookingError)) throw error
    equal(error.code, 'line_friend_required', 'friend error')
    equal(error.status, 409, 'friend status')
    equal(inserts, 0, 'no insert')
  }
})

Deno.test('Tuesday-only period is rejected on another weekday', async () => {
  try {
    await createBooking({ ...validInput, date:'2026-09-09' }, 'customer-uuid', { channelId:'1234567890' }, {
      loadLineLink: async () => ({ lineUserId:'U12345678' }),
      verifyAccess: async () => ({ friend:true }),
      insertPendingBooking: async () => ({}),
    })
    throw new Error('expected invalid Tuesday period')
  } catch (error) {
    if (!(error instanceof CreateBookingError)) throw error
    equal(error.code, 'invalid_slot', 'Tuesday-only error')
    equal(error.status, 400, 'invalid slot status')
  }
})

Deno.test('design image path must belong to the authenticated booking', async () => {
  try {
    await createBooking({ ...validInput, designImagePath:'another-user/booking/image.jpg' }, 'customer-uuid', { channelId:'1234567890' }, {
      loadLineLink: async () => ({ lineUserId:'U12345678' }),
      verifyAccess: async () => ({ friend:true }),
      insertPendingBooking: async () => ({}),
    })
    throw new Error('expected image path rejection')
  } catch (error) {
    if (!(error instanceof CreateBookingError)) throw error
    equal(error.code, 'invalid_design_image', 'image ownership error')
  }
})
