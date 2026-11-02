import { withSupabase } from '@supabase/server'
import { LineApiError, verifyLineAccess, verifyLineIdToken } from '../_shared/line-messaging.ts'
import { linkLineCustomer, LinkCustomerError } from './core.ts'

type Body = { idToken?: string; accessToken?: string }

export default {
  fetch: withSupabase({ auth: 'user' }, async (req, ctx) => {
    if (req.method !== 'POST') return Response.json({ message:'method_not_allowed' }, { status:405 })
    let body: Body
    try { body = await req.json() as Body } catch {
      return Response.json({ message:'invalid_request' }, { status:400 })
    }

    const claims = (ctx.userClaims ?? ctx.jwtClaims ?? {}) as { sub?: string; id?: string }
    const userId = claims.sub ?? claims.id
    const admin = ctx.supabaseAdmin as any
    const channelId = Deno.env.get('LINE_LOGIN_CHANNEL_ID') || ''
    if (!userId) return Response.json({ message:'auth_required' }, { status:401 })
    if (!channelId) return Response.json({ message:'line_configuration_missing' }, { status:500 })

    try {
      const result = await linkLineCustomer(body, userId, { channelId }, {
        verifyIdToken: verifyLineIdToken,
        verifyAccess: verifyLineAccess,
        linkCustomer: async ({ customerId, lineUserId, verifiedAt }) => {
          const { error } = await admin.rpc('demo_link_line_customer', {
            p_customer_id:customerId,
            p_line_user_id:lineUserId,
            p_verified_at:verifiedAt,
          })
          if (error) throw new LinkCustomerError('line_link_failed', 500)
        },
      })
      return Response.json(result)
    } catch (error) {
      if (error instanceof LinkCustomerError) {
        return Response.json({ message:error.code }, { status:error.status })
      }
      if (error instanceof LineApiError) {
        return Response.json({ message:error.code }, { status:error.status === 401 ? 401 : 502 })
      }
      return Response.json({ message:'line_link_failed' }, { status:500 })
    }
  }),
}
