import { withSupabase } from '@supabase/server'

export default {
  fetch: withSupabase({ auth: 'none' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    const secret = Deno.env.get('RESCHEDULE_CRON_SECRET') || ''
    const supplied = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i,'')
    if (!secret || supplied !== secret) return Response.json({ message:'forbidden' }, { status:403 })
    const { data, error } = await ctx.supabaseAdmin.rpc('expire_demo_reschedules')
    if (error) return Response.json({ message:'reschedule_expiry_failed' }, { status:500 })
    return Response.json({ expiredCount:Number(data || 0) })
  }),
}
