import { withSupabase } from '@supabase/server'
import { pushLineText } from '../_shared/line-messaging.ts'
import { previousMonth, summaryText, type Row } from './core.ts'
import { equalSecret } from '../_shared/cron-secret.ts'

// Called by pg_cron on the 1st of each month with the same secret as send-line-notifications.
export default {
  fetch: withSupabase({ auth:'none' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    const secret = Deno.env.get('LINE_CRON_SECRET') || ''
    const token = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') || ''
    const owner = Deno.env.get('LINE_OWNER_USER_ID') || ''
    if (!secret || !token || !/^U[0-9a-f]{32}$/.test(owner)) return Response.json({ message:'line_configuration_missing' }, { status:500 })
    if (!await equalSecret(req.headers.get('x-demo-cron-secret') || '', secret)) return Response.json({ message:'forbidden' }, { status:403 })
    const month = previousMonth(new Date())
    const { data, error } = await ctx.supabaseAdmin.from('demo_bookings')
      .select('status,paid_at,slot_date,attendance,refund_status,cancelled_by_role')
      .gte('slot_date', month.from).lt('slot_date', month.to)
    if (error) return Response.json({ message:'summary_query_failed' }, { status:500 })
    const text = summaryText((data || []) as Row[], month.label, Number(Deno.env.get('DEMO_DEPOSIT') || 150))
    await pushLineText(owner, text, token, crypto.randomUUID()) // LINE retry keys must be UUIDs
    return Response.json({ sent:true, month:month.from })
  }),
}
