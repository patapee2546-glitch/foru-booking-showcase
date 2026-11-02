import { checkSlip, classifySlip } from './slip-check.ts'

function equal(actual: unknown, expected: unknown, label: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${label}: ${JSON.stringify(actual)} !== ${JSON.stringify(expected)}`)
}
const ok = (amount: number) => ({ success: true, data: { success: true, transRef: 'T1', amount } })

Deno.test('a real transfer that covers the deposit passes', () => {
  equal(classifySlip(ok(150), 150).status, 'verified', 'exact deposit')
  equal(classifySlip(ok(200), 150).transRef, 'T1', 'keeps the transfer reference for duplicate checks')
})

Deno.test('a transfer below the deposit is flagged', () => {
  const v = classifySlip(ok(100), 150)
  equal([v.status, v.code], ['rejected', 'AMOUNT_LOW'], 'low amount')
})

Deno.test('slip problems are flagged, bank or account problems go to the owner', () => {
  equal(classifySlip({ success: false, code: 1012, message: 'dup' }, 150).status, 'rejected', 'reused slip')
  equal(classifySlip({ success: false, code: 1014 }, 150).status, 'rejected', 'wrong receiver')
  equal(classifySlip({ success: false, code: 1009 }, 150).status, 'unverified', 'bank outage')
  equal(classifySlip({ success: false, code: 1004 }, 150).status, 'unverified', 'quota used up')
  equal(classifySlip(null, 150).status, 'unverified', 'unreadable reply')
})

Deno.test('a re-check accepts its own earlier attempt, a first check does not', () => {
  const dup = { success: false, code: 1012, data: { transRef: 'T9', amount: 150 } }
  equal(classifySlip(dup, 150).status, 'rejected', 'first check: duplicate is rejected')
  equal(classifySlip(dup, 150, true).status, 'verified', 're-check: our own earlier attempt')
  equal(classifySlip({ success: false, code: 1012 }, 150, true).status, 'rejected', 're-check without slip data stays rejected')
})

Deno.test('no SlipOK setup keeps the manual check; network errors never reject', async () => {
  equal(await checkSlip(new Blob(['x']), 150, {}), null, 'not configured')
  const down = async () => { throw new Error('offline') }
  equal((await checkSlip(new Blob(['x']), 150, { branchId: 'b', apiKey: 'k' }, down))?.status, 'unverified', 'network')
  let sent: { url?: string, key?: string } = {}
  const fake = async (url: string, init: RequestInit) => { sent = { url, key: (init.headers as Record<string, string>)['x-authorization'] }; return Response.json(ok(150)) }
  equal((await checkSlip(new Blob(['x']), 150, { branchId: 'b 1', apiKey: 'k' }, fake))?.status, 'verified', 'happy path')
  equal(sent, { url: 'https://api.slipok.com/api/line/apikey/b%201', key: 'k' }, 'endpoint and auth header')
})
