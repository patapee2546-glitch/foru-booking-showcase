import { withSupabase } from '@supabase/server'

type Body = { requestId?: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: Body
    try { body = await req.json() as Body } catch { return Response.json({ message:'invalid_request' }, { status:400 }) }
    const requestId = String(body.requestId || '').trim()
    const userId = ctx.userClaims?.sub ?? ctx.userClaims?.id ?? ctx.jwtClaims?.sub
    if (!userId || !UUID.test(requestId)) return Response.json({ message:'invalid_request' }, { status:400 })
    const now = new Date().toISOString()
    const { data: request, error } = await ctx.supabaseAdmin.from('demo_reschedule_requests')
      .update({ status: 'cancelled', updated_at:now })
      .eq('id',requestId).eq('customer_id', userId).in('status', ['awaiting_slip', 'pending_review'])
      .select('*').maybeSingle()
    if (error) return Response.json({ message:'reschedule_cancel_failed' }, { status:500 })
    if (!request) return Response.json({ message:'request_not_cancellable' }, { status:409 })
    const { error: slotError } = await ctx.supabaseAdmin.from('demo_slots')
      .update({ is_open:true, updated_at:now })
      .eq('slot_date',request.new_slot_date).eq('start_time',request.new_start_time)
    if (slotError) return Response.json({ message:'slot_reopen_failed' }, { status:500 })
    if (request.slip_path) await ctx.supabaseAdmin.storage.from('demo-reschedule-slips').remove([request.slip_path])
    return Response.json({ request })
  }),
}
