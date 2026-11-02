import { withSupabase } from '@supabase/server'
import { LineApiError, verifyLineAccess } from '../_shared/line-messaging.ts'
import { createBooking, CreateBookingError, type CreateBookingInput } from './core.ts'

export default {
  fetch: withSupabase({ auth:'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: CreateBookingInput
    try { body = await req.json() as CreateBookingInput } catch {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }
    const claims = (ctx.userClaims ?? ctx.jwtClaims ?? {}) as { sub?: string; id?: string }
    const userId = claims.sub ?? claims.id
    const admin = ctx.supabaseAdmin as any
    const channelId = Deno.env.get('LINE_LOGIN_CHANNEL_ID') || ''
    if (!userId) return Response.json({ message:'auth_required' }, { status:401 })
    if (!channelId) return Response.json({ message:'line_configuration_missing' }, { status:500 })

    try {
      const booking = await createBooking(body, userId, { channelId }, {
        loadLineLink: async customerId => {
          const { data, error } = await admin
            .from('demo_line_links')
            .select('line_user_id')
            .eq('customer_id', customerId)
            .maybeSingle()
          if (error) throw new CreateBookingError('line_link_lookup_failed', 500)
          return data?.line_user_id ? { lineUserId:data.line_user_id } : null
        },
        verifyAccess: verifyLineAccess,
        insertPendingBooking: async args => {
          const { data, error } = await admin.rpc('demo_create_booking_with_promo', {
            p_customer_id:args.customerId,
            p_booking_id:args.bookingId,
            p_slot_date:args.date,
            p_start_time:args.start,
            p_customer_name:args.name,
            p_customer_phone:args.phone,
            p_removal_service:args.removalService,
            p_design_image_path:args.designImagePath,
            p_benefit:args.benefit || null,
          })
          if (error) {
            const detail = error.message || ''
            const promoError=detail.match(/\bPROMO_[A-Z_]+\b/)?.[0]
            if(promoError)throw new CreateBookingError(promoError,409)
            if (error.code === '23505' || detail.includes('SLOT_CLOSED')) throw new CreateBookingError('slot_closed', 409)
            if (detail.includes('LINE_FRIEND_REQUIRED')) throw new CreateBookingError('line_friend_required', 409)
            throw new CreateBookingError('booking_create_failed', 500)
          }
          // the ad / channel this customer came from (?ref= on the booking link); a bad value is just dropped
          const source = String((body as { source?: unknown }).source ?? '').toLowerCase()
          if (/^[a-z0-9_-]{1,30}$/.test(source)) await admin.from('demo_bookings').update({ source }).eq('id', args.bookingId)
          return data as Record<string, unknown>
        },
      })
      return Response.json(booking)
    } catch (error) {
      if (error instanceof CreateBookingError) return Response.json({ message:error.code }, { status:error.status })
      if (error instanceof LineApiError) return Response.json({ message:error.code }, { status:error.status === 401 ? 401 : 502 })
      return Response.json({ message:'booking_create_failed' }, { status:500 })
    }
  }),
}
