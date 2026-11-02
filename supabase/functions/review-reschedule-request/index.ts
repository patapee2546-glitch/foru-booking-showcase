import { withSupabase } from '@supabase/server'

type Body = { requestId?: string; decision?: string }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: Body
    try { body = await req.json() as Body } catch { return Response.json({ message:'invalid_request' }, { status:400 }) }
    const requestId = String(body.requestId || '').trim()
    const decision = String(body.decision || '').trim()
    const userId = ctx.userClaims?.sub ?? ctx.userClaims?.id ?? ctx.jwtClaims?.sub
    const appMetadata = (ctx.jwtClaims?.app_metadata ?? ctx.userClaims?.app_metadata) as { role?: unknown } | undefined
    if (appMetadata?.role !== 'owner') return Response.json({ message:'forbidden' }, { status:403 })
    if (!userId || !UUID.test(requestId) || (decision !== 'approve' && decision !== 'reject')) {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }
    const { data, error } = await ctx.supabaseAdmin.rpc('review_demo_reschedule', {
      p_request_id:requestId, p_decision:decision, p_owner_id:userId,
    })
    if (error) {
      const detail = error.message || ''
      if (detail.includes('REQUEST_NOT_REVIEWABLE') || detail.includes('BOOKING_CHANGED')) return Response.json({ message:'request_not_reviewable' }, { status:409 })
      return Response.json({ message:'reschedule_review_failed' }, { status:500 })
    }
    return Response.json(data)
  }),
}
