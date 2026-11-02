import { withSupabase } from '@supabase/server'

type Body = { requestId?: string; slipPath?: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: Body
    try { body = await req.json() as Body } catch { return Response.json({ message:'invalid_request' }, { status:400 }) }
    const requestId = String(body.requestId || '').trim()
    const slipPath = String(body.slipPath || '').trim()
    const userId = ctx.userClaims?.sub ?? ctx.userClaims?.id ?? ctx.jwtClaims?.sub
    if (!userId || !UUID.test(requestId) || !slipPath.startsWith(`${userId}/${requestId}/`)) {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }
    const { data: object, error: objectError } = await ctx.supabaseAdmin.storage.from('demo-reschedule-slips').download(slipPath)
    if (objectError?.statusCode === '404' || !object) return Response.json({ message:'slip_not_found' }, { status:404 })
    if (objectError) return Response.json({ message:'slip_lookup_failed' }, { status:500 })
    const { data, error } = await ctx.supabaseAdmin.rpc('submit_demo_reschedule_slip', {
      p_request_id: requestId, p_customer_id: userId, p_slip_path: slipPath,
    })
    if (error) {
      const conflict = /REQUEST_EXPIRED|BOOKING_CHANGED|NEW_SLOT_UNAVAILABLE|RESCHEDULE_DEADLINE_PASSED/.test(error.message || '')
      return Response.json({ message: conflict ? 'เลื่อนคิวไม่สำเร็จ กรุณาตรวจสอบเวลาและรอบว่าง คิวเดิมยังอยู่' : 'slip_submit_failed' }, { status:conflict ? 409 : 500 })
    }
    if (!data) return Response.json({ message:'request_expired' }, { status:409 })
    const owner = Deno.env.get('LINE_OWNER_USER_ID') || ''
    if (/^U[0-9a-f]{32}$/.test(owner)) {
      const { data: request } = await ctx.supabaseAdmin.from('demo_reschedule_requests').select('booking_id').eq('id', requestId).maybeSingle()
      // ponytail: one row per booking+type, so a later reschedule re-arms the same row instead of adding a new one
      if (request?.booking_id) await ctx.supabaseAdmin.from('demo_line_notifications').upsert({
        booking_id: request.booking_id, recipient_line_user_id: owner, notification_type: 'owner_booking_rescheduled',
        scheduled_for: new Date().toISOString(), status: 'pending', attempt_count: 0, last_error: null, sent_at: null,
      }, { onConflict: 'booking_id,notification_type,recipient_line_user_id' })
    }
    return Response.json(data)
  }),
}
