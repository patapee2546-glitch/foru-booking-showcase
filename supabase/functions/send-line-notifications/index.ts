import { withSupabase } from '@supabase/server'
import { sendNotificationJob, type NotificationJob } from '../_shared/line-notification.ts'
import { processNotificationBatch } from './core.ts'
import { equalSecret } from '../_shared/cron-secret.ts'
import { pushLineText } from '../_shared/line-messaging.ts'
import { checkSlip } from '../_shared/slip-check.ts'

// Re-check slips the bank or SlipOK could not answer (1009 / 1010 / network): every 10 minutes, up to 3 tries.
async function recheckSlips(admin: any) {
  const cfg = { branchId: Deno.env.get('SLIPOK_BRANCH_ID') || '', apiKey: Deno.env.get('SLIPOK_API_KEY') || '' }
  if (!cfg.branchId || !cfg.apiKey) return 0
  const { data } = await admin.rpc('demo_slip_rechecks_due', { p_limit: 3 })
  let done = 0
  for (const row of (data || []) as { id: string, slip_path: string }[]) {
    const { data: image } = await admin.storage.from('demo-payment-slips').download(row.slip_path)
    if (!image) continue
    const v = await checkSlip(image as Blob, Number(Deno.env.get('DEMO_DEPOSIT') || 150), cfg, fetch, 10000, true)
    if (!v) continue
    await admin.rpc('demo_record_slip_check', {
      p_booking_id: row.id, p_status: v.status, p_code: v.code, p_message: v.message,
      p_trans_ref: v.transRef ?? null, p_owner_line_user_id: Deno.env.get('LINE_OWNER_USER_ID') || '',
    })
    done += 1
  }
  return done
}

// One scheduled promo per minute run, pushed to every past customer on LINE.
// ponytail: one push per person (fine for a few hundred); switch to LINE multicast (500 ids per call) when audiences grow
async function sendDueBroadcast(admin: any, token: string) {
  const { data: job, error } = await admin.rpc('demo_claim_due_broadcast')
  if (error || !job?.id) return null
  const { data: audience } = await admin.rpc('demo_broadcast_audience')
  const ids = ((audience || []) as { line_user_id: string }[]).map(row => row.line_user_id)
  let sent = 0
  for (const id of ids) {
    try { await pushLineText(id, job.message, token, crypto.randomUUID()); sent += 1 } catch { /* blocked or unfollowed: skip */ }
  }
  await admin.from('demo_promo_broadcasts')
    .update({ status: sent || !ids.length ? 'sent' : 'failed', recipients: ids.length, sent_count: sent })
    .eq('id', job.id)
  return { id: job.id, recipients: ids.length, sent }
}


export default {
  fetch: withSupabase({ auth:'none' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    const expectedSecret = Deno.env.get('LINE_CRON_SECRET') || ''
    const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') || ''
    const suppliedSecret = req.headers.get('x-demo-cron-secret') || ''
    if (!expectedSecret || !channelAccessToken) {
      return Response.json({ message:'line_configuration_missing' }, { status:500 })
    }
    if (!suppliedSecret || !await equalSecret(suppliedSecret, expectedSecret)) {
      return Response.json({ message:'forbidden' }, { status:403 })
    }

    const admin = ctx.supabaseAdmin as any
    const { data, error } = await admin.rpc('demo_claim_due_line_notifications', { p_limit:25 })
    if (error) return Response.json({ message:'notification_claim_failed' }, { status:500 })
    const jobs = (data || []) as NotificationJob[]
    const result = await processNotificationBatch(jobs, {
      sendJob: job => sendNotificationJob(admin, job, {
        channelAccessToken,
        reviewUrl: Deno.env.get('DEMO_REVIEW_URL') || '',
        bookingUrl: Deno.env.get('DEMO_BOOKING_URL') || 'https://demo-nails.example.com/',
      }),
      finishJob: async args => {
        const { error: finishError } = await admin.rpc('demo_finish_line_notification', {
          p_id:args.id,
          p_sent:args.sent,
          p_error:args.error,
          p_retryable:args.retryable,
        })
        if (finishError) throw new Error('notification_finish_failed')
      },
      cancelJob: async id => {
        const { error: cancelError } = await admin.rpc('demo_cancel_line_notification', { p_id:id })
        if (cancelError) throw new Error('notification_cancel_failed')
      },
    })
    const broadcast = await sendDueBroadcast(admin, channelAccessToken)
    const slipRechecks = await recheckSlips(admin).catch(() => 0)
    return Response.json({ ...result, broadcast, slipRechecks })
  }),
}
