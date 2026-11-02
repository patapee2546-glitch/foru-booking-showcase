// Automatic slip check through SlipOK (https://slipok.com/api-documentation/check-slip/).
// Pass = SlipOK confirms a real transfer into the shop's account (log=true also blocks reused slips)
// and the amount covers the deposit. A failed slip never cancels the booking: the owner decides.

export type SlipVerdict = {
  status: 'verified' | 'rejected' | 'unverified'
  code: string
  message: string
  transRef?: string
  amount?: number
}

// slip problems -> rejected; anything else (bank delay, quota, auth, network) -> owner checks by hand
const SLIP_PROBLEM = new Set([1005, 1006, 1007, 1008, 1011, 1012, 1013, 1014])
const MESSAGE: Record<number, string> = {
  1005: 'ไฟล์ที่แนบไม่ใช่รูปภาพ',
  1006: 'รูปสลิปอ่านไม่ได้',
  1007: 'ไม่พบ QR บนสลิป',
  1008: 'QR ไม่ใช่สลิปโอนเงิน',
  1009: 'ระบบธนาคารขัดข้องชั่วคราว · ระบบจะตรวจซ้ำให้เอง',
  1010: 'ธนาคารยังไม่ส่งข้อมูลรายการนี้ · ระบบจะตรวจซ้ำให้เอง',
  1011: 'สลิปหมดอายุ หรือไม่พบรายการโอน',
  1012: 'สลิปนี้เคยถูกใช้แล้ว (สลิปซ้ำ)',
  1013: 'ยอดเงินในสลิปไม่ตรง',
  1014: 'โอนเข้าบัญชีอื่น ไม่ใช่บัญชีร้าน',
}

// retry: a re-check of a slip whose first attempt timed out. SlipOK may already have logged it, so its
// "duplicate" (1012, which carries the slip data) is our own earlier attempt; reuse by another booking is
// still caught by the transfer reference in the database.
export function classifySlip(body: unknown, deposit: number, retry = false): SlipVerdict {
  const b = (body ?? {}) as { success?: boolean, code?: number | string, message?: string, data?: Record<string, unknown> }
  const data = b.data ?? {}
  const transRef = typeof data.transRef === 'string' && data.transRef ? data.transRef : undefined
  const ownDuplicate = retry && Number(b.code) === 1012 && transRef !== undefined && data.amount !== undefined
  if ((b.success === true && data.success !== false) || ownDuplicate) {
    const amount = Number(data.amount)
    if (!(amount >= deposit)) {
      return { status: 'rejected', code: 'AMOUNT_LOW', message: `ยอดโอน ฿${Number.isFinite(amount) ? amount : 0} น้อยกว่ามัดจำ ฿${deposit}`, transRef, amount }
    }
    return { status: 'verified', code: 'OK', message: `ตรวจผ่านอัตโนมัติ · ฿${amount}`, transRef, amount }
  }
  const code = Number(b.code)
  return {
    status: SLIP_PROBLEM.has(code) ? 'rejected' : 'unverified',
    code: Number.isFinite(code) && code ? String(code) : 'UNKNOWN',
    message: MESSAGE[code] ?? 'ตรวจสลิปอัตโนมัติไม่สำเร็จ · ตรวจเองในหลังบ้าน',
    transRef,
  }
}

type Fetch = (url: string, init: RequestInit) => Promise<Response>

export async function checkSlip(
  image: Blob,
  deposit: number,
  cfg: { branchId?: string, apiKey?: string },
  fetchImpl: Fetch = fetch,
  timeoutMs = 10000,
  retry = false,
): Promise<SlipVerdict | null> {
  if (!cfg.branchId || !cfg.apiKey) return null // not set up yet: keep today's manual check
  const form = new FormData()
  form.append('files', image, 'slip.jpg')
  form.append('log', 'true')
  try {
    const res = await fetchImpl(`https://api.slipok.com/api/line/apikey/${encodeURIComponent(cfg.branchId)}`, {
      method: 'POST',
      headers: { 'x-authorization': cfg.apiKey },
      body: form,
      signal: AbortSignal.timeout(timeoutMs),
    })
    return classifySlip(await res.json().catch(() => null), deposit, retry)
  } catch {
    return { status: 'unverified', code: 'NETWORK', message: 'ติดต่อระบบตรวจสลิปไม่ได้ · ระบบจะตรวจซ้ำให้เอง' }
  }
}
