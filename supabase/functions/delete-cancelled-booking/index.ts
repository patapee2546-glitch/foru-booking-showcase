import { withSupabase } from '@supabase/server'

type DeleteBody = { bookingId?: string }
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message: 'method_not_allowed' }, { status: 405 })
    let body: DeleteBody
    try { body = await req.json() as DeleteBody }
    catch { return Response.json({ message: 'invalid_request' }, { status: 400 }) }
    const bookingId = typeof body?.bookingId === 'string' ? body.bookingId.trim() : ''
    const appMetadata = (ctx.jwtClaims?.app_metadata ?? ctx.userClaims?.app_metadata) as { role?: unknown } | undefined
    if (!UUID_PATTERN.test(bookingId)) return Response.json({ message: 'invalid_request' }, { status: 400 })
    if (appMetadata?.role !== 'owner') return Response.json({ message: 'forbidden' }, { status: 403 })

    const { data: booking, error: lookupError } = await ctx.supabaseAdmin
      .from('demo_bookings').select('id,status,slip_path').eq('id', bookingId).maybeSingle()
    if (lookupError) return Response.json({ message: 'booking_lookup_failed' }, { status: 500 })
    if (!booking) return Response.json({ deleted: true })
    if (booking.status !== 'cancelled') return Response.json({ message: 'only_cancelled_history_can_be_deleted' }, { status: 409 })

    if (booking.slip_path) {
      const { error: slipError } = await ctx.supabaseAdmin.storage.from('demo-payment-slips').remove([booking.slip_path])
      if (slipError) return Response.json({ message: 'slip_delete_failed' }, { status: 500 })
    }
    const { error: deleteError } = await ctx.supabaseAdmin.from('demo_bookings').delete().eq('id', bookingId).eq('status', 'cancelled')
    if (deleteError) return Response.json({ message: 'delete_failed' }, { status: 500 })
    return Response.json({ deleted: true })
  }),
}
