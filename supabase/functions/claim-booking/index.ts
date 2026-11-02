import { withSupabase } from '@supabase/server'
import { sendNotificationJob, type NotificationJob } from '../_shared/line-notification.ts'
import { checkSlip } from '../_shared/slip-check.ts'

type ClaimBody = { bookingId?: string; slipPath?: string }
type ClaimStatus = 'approved' | 'lost' | 'expired'
type ClaimResult = { won: boolean; status: ClaimStatus }

function result(value: ClaimResult, httpStatus = 200) {
  return Response.json(value, { status:httpStatus })
}

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: ClaimBody
    try { body = await req.json() as ClaimBody } catch {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }

    const bookingId = typeof body.bookingId === 'string' ? body.bookingId.trim() : ''
    const slipPath = typeof body.slipPath === 'string' ? body.slipPath.trim() : ''
    const claims = (ctx.userClaims ?? ctx.jwtClaims ?? {}) as { sub?: string; id?: string }
    const userId = claims.sub ?? claims.id
    // @supabase/server cannot infer project RPCs without generated Database types.
    // Keep the untyped boundary here; tested business logic remains typed.
    const admin = ctx.supabaseAdmin as any
    if (!bookingId || !slipPath || !userId || !slipPath.startsWith(`${userId}/${bookingId}/`)) {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }

    const { data: slipObject, error: slipError } = await admin.storage
      .from('demo-payment-slips')
      .download(slipPath)
    if (slipError?.statusCode === '404' || !slipObject) {
      return Response.json({ message:'slip_not_found' }, { status:404 })
    }
    if (slipError) return Response.json({ message:'slip_lookup_failed' }, { status:500 })

    const { data, error } = await admin.rpc('demo_claim_booking_with_owner_notification', {
      p_booking_id:bookingId,
      p_customer_id:userId,
      p_slip_path:slipPath,
      p_owner_line_user_id:Deno.env.get('LINE_OWNER_USER_ID') || '',
    })
    if (error) return Response.json({ message:'claim_failed' }, { status:500 })
    const claim = data as ClaimResult

    if (!claim?.won) {
      const { error: removeError } = await admin.storage.from('demo-payment-slips').remove([slipPath])
      if (removeError) return Response.json({ message:'slip_cleanup_failed' }, { status:500 })
      return result(claim || { won:false, status:'lost' }, 409)
    }

    // automatic slip check (SlipOK). The booking is already confirmed; this only marks the payment
    // verified / rejected (owner alerted on LINE). Skipped until SLIPOK_BRANCH_ID + SLIPOK_API_KEY are set.
    try {
      const verdict = await checkSlip(slipObject as Blob, Number(Deno.env.get('DEMO_DEPOSIT') || 150), {
        branchId: Deno.env.get('SLIPOK_BRANCH_ID') || '',
        apiKey: Deno.env.get('SLIPOK_API_KEY') || '',
      })
      if (verdict) {
        await admin.rpc('demo_record_slip_check', {
          p_booking_id: bookingId, p_status: verdict.status, p_code: verdict.code, p_message: verdict.message,
          p_trans_ref: verdict.transRef ?? null, p_owner_line_user_id: Deno.env.get('LINE_OWNER_USER_ID') || '',
        })
      }
    } catch {
      // a failed check leaves the payment 'unverified' for the owner, exactly like before
    }

    const channelAccessToken = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') || ''
    if (channelAccessToken) {
      try {
        const { data: queued } = await admin
          .from('demo_line_notifications')
          .select('id')
          .eq('booking_id', bookingId)
          .eq('notification_type', 'booking_confirmed')
          .eq('status', 'pending')
          .maybeSingle()
        if (queued?.id) {
          const { data: claimedJob } = await admin.rpc('demo_claim_line_notification', { p_id:queued.id })
          if (claimedJob?.id) {
            const job = claimedJob as NotificationJob
            const outcome = await sendNotificationJob(admin, job, { channelAccessToken })
            if (outcome === 'cancelled') {
              await admin.rpc('demo_cancel_line_notification', { p_id:job.id })
            } else {
              await admin.rpc('demo_finish_line_notification', {
                p_id:job.id,
                p_sent:outcome === 'sent',
                p_error:outcome === 'sent' ? null : outcome,
                p_retryable:outcome === 'retryable',
              })
            }
          }
        }
      } catch {
        // Approval is authoritative. A stuck processing job is reclaimed after five minutes.
      }
    }

    return result(claim)
  }),
}
