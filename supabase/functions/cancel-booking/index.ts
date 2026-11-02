import { withSupabase } from '@supabase/server'

type CancelBody = { bookingId?: string }
type CallerRole = 'customer' | 'owner'
type RefundStatus = 'refund_due' | 'no_refund'
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function cancelledResult(refundStatus: RefundStatus, cancelledByRole: CallerRole, httpStatus = 200) {
  return Response.json({ status: 'cancelled', refundStatus, cancelledByRole }, { status: httpStatus })
}

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message: 'method_not_allowed' }, { status: 405 })

    let body: CancelBody
    try {
      body = await req.json() as CancelBody
    } catch {
      return Response.json({ message: 'invalid_request' }, { status: 400 })
    }

    const bookingId = typeof body?.bookingId === 'string' ? body.bookingId.trim() : ''
    const userId = ctx.userClaims?.sub ?? ctx.userClaims?.id
    if (!bookingId || !UUID_PATTERN.test(bookingId) || !userId) {
      return Response.json({ message: 'invalid_request' }, { status: 400 })
    }

    const appMetadata = (ctx.jwtClaims?.app_metadata ?? ctx.userClaims?.app_metadata) as { role?: unknown } | undefined
    const isOwner = appMetadata?.role === 'owner'
    const now = new Date().toISOString()

    const { data: booking, error: bookingError } = await ctx.supabaseAdmin
      .from('demo_bookings')
      .select('id,customer_id,slot_date,start_time,status')
      .eq('id', bookingId)
      .maybeSingle()

    if (bookingError) return Response.json({ message: 'booking_lookup_failed' }, { status: 500 })
    if (!booking) return Response.json({ message: 'booking_not_found' }, { status: 404 })
    if (!isOwner && booking.customer_id !== userId) return Response.json({ message: 'forbidden' }, { status: 403 })
    if (booking.status !== 'pending' && booking.status !== 'approved') {
      return Response.json({ message: 'booking_not_cancellable', currentStatus: booking.status }, { status: 409 })
    }

    const startHHMM = String(booking.start_time).slice(0, 5)
    // Asia/Bangkok has a fixed +07:00 offset, so this is server-timezone independent.
    const appointmentMilliseconds = Date.parse(`${booking.slot_date}T${startHHMM}:00+07:00`)
    if (Number.isNaN(appointmentMilliseconds)) {
      return Response.json({ message: 'booking_time_invalid' }, { status: 500 })
    }
    const refundStatus: RefundStatus = appointmentMilliseconds - Date.now() >= 48 * 60 * 60 * 1000
      ? 'refund_due'
      : 'no_refund'
    const cancelledByRole: CallerRole = isOwner ? 'owner' : 'customer'

    const { data: cancelledBooking, error: cancelError } = await (ctx.supabaseAdmin as any)
      .rpc('demo_cancel_booking_and_notify', {
        p_booking_id:bookingId,
        p_actor_id:userId,
        p_actor_role:cancelledByRole,
        p_refund_status:refundStatus,
        p_owner_line_user_id:Deno.env.get('LINE_OWNER_USER_ID') || '',
      })

    if (cancelError) return Response.json({ message: 'cancel_failed' }, { status: 500 })
    if (cancelledBooking) {
      const { error: reopenError } = await ctx.supabaseAdmin
        .from('demo_slots')
        .update({ is_open: true, updated_at: now })
        .eq('slot_date', booking.slot_date)
        .eq('start_time', booking.start_time)
      if (reopenError) return Response.json({ message: 'slot_reopen_failed' }, { status: 500 })
      return cancelledResult(refundStatus, cancelledByRole)
    }

    const { data: current, error: currentError } = await ctx.supabaseAdmin
      .from('demo_bookings')
      .select('status,refund_status,cancelled_by_role')
      .eq('id', bookingId)
      .maybeSingle()
    if (currentError) return Response.json({ message: 'booking_lookup_failed' }, { status: 500 })
    if (current?.status === 'cancelled' &&
      (current.refund_status === 'refund_due' || current.refund_status === 'no_refund') &&
      (current.cancelled_by_role === 'customer' || current.cancelled_by_role === 'owner')) {
      return cancelledResult(current.refund_status, current.cancelled_by_role, 409)
    }
    return Response.json({ message: 'booking_not_cancellable', currentStatus: current?.status ?? 'not_found' }, { status: 409 })
  }),
}
