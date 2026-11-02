import { withSupabase } from '@supabase/server'

type Body = { bookingId?: string; newDate?: string; newStart?: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const DATE = /^\d{4}-\d{2}-\d{2}$/
const STARTS = new Set(['10:00','13:30','15:00','17:00','19:00','20:00'])

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: Body
    try { body = await req.json() as Body } catch { return Response.json({ message:'invalid_request' }, { status:400 }) }
    const bookingId = String(body.bookingId || '').trim()
    const newDate = String(body.newDate || '').trim()
    const newStart = String(body.newStart || '').slice(0,5)
    const isTuesday = DATE.test(newDate) && new Date(`${newDate}T12:00:00Z`).getUTCDay() === 2
    const claims = (ctx.userClaims ?? ctx.jwtClaims ?? {}) as { sub?: string; id?: string }
    const userId = claims.sub ?? claims.id
    // @supabase/server cannot infer project RPCs without generated Database types.
    const admin = ctx.supabaseAdmin as any
    if (!userId || !UUID.test(bookingId) || !DATE.test(newDate) || !STARTS.has(newStart) || (['15:00','19:00'].includes(newStart) && !isTuesday)) {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }
    const { data, error } = await admin.rpc('create_demo_reschedule', {
      p_booking_id: bookingId,
      p_customer_id: userId,
      p_new_slot_date: newDate,
      p_new_start_time: `${newStart}:00`,
    })
    if (error) {
      const detail = `${error.code || ''} ${error.message || ''}`
      if (error.code === '23505' || detail.includes('NEW_SLOT_UNAVAILABLE')) return Response.json({ message:'slot_unavailable' }, { status:409 })
      if (detail.includes('RESCHEDULE_DEADLINE_PASSED')) return Response.json({ message:'reschedule_deadline_passed' }, { status:409 })
      if (detail.includes('BOOKING_NOT_ELIGIBLE')) return Response.json({ message:'booking_not_eligible' }, { status:409 })
      return Response.json({ message:'reschedule_create_failed' }, { status:500 })
    }
    return Response.json({ request:data })
  }),
}
