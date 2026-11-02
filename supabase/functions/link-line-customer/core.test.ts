import { linkLineCustomer, LinkCustomerError } from './core.ts'

function equal(actual: unknown, expected: unknown, label: string) {
  if (actual !== expected) throw new Error(`${label}: expected ${expected}, got ${actual}`)
}

Deno.test('verified friend is linked to the authenticated customer', async () => {
  const rpcCalls: Array<Record<string, unknown>> = []
  const result = await linkLineCustomer(
    { idToken: 'id-token', accessToken: 'access-token' },
    'customer-uuid',
    { channelId: '1234567890' },
    {
      verifyIdToken: async () => ({ lineUserId: 'U12345678' }),
      verifyAccess: async () => ({ friend: true }),
      linkCustomer: async (args) => { rpcCalls.push(args) },
    },
  )
  equal(result.linked, true, 'linked response')
  equal(rpcCalls.length, 1, 'single atomic link write')
  equal(rpcCalls[0].customerId, 'customer-uuid', 'authenticated customer')
  equal(rpcCalls[0].lineUserId, 'U12345678', 'verified LINE user')
})

Deno.test('non-friend cannot create a LINE link', async () => {
  let writes = 0
  try {
    await linkLineCustomer(
      { idToken: 'id-token', accessToken: 'access-token' },
      'customer-uuid',
      { channelId: '1234567890' },
      {
        verifyIdToken: async () => ({ lineUserId: 'U12345678' }),
        verifyAccess: async () => ({ friend: false }),
        linkCustomer: async () => { writes += 1 },
      },
    )
    throw new Error('expected linkLineCustomer to reject a non-friend')
  } catch (error) {
    if (!(error instanceof LinkCustomerError)) throw error
    equal(error.code, 'line_friend_required', 'friend error')
    equal(error.status, 409, 'friend HTTP status')
    equal(writes, 0, 'no link written')
  }
})

Deno.test('empty tokens are rejected before LINE or database calls', async () => {
  let calls = 0
  try {
    await linkLineCustomer(
      { idToken: '', accessToken: '' },
      'customer-uuid',
      { channelId: '1234567890' },
      {
        verifyIdToken: async () => { calls += 1; return { lineUserId: 'U12345678' } },
        verifyAccess: async () => { calls += 1; return { friend: true } },
        linkCustomer: async () => { calls += 1 },
      },
    )
    throw new Error('expected invalid request')
  } catch (error) {
    if (!(error instanceof LinkCustomerError)) throw error
    equal(error.code, 'invalid_request', 'invalid token error')
    equal(calls, 0, 'external calls')
  }
})
