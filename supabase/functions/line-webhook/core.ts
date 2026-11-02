// Pure helpers for the LINE webhook (tested in core.test.ts)
const enc = new TextEncoder()

export async function validSignature(body: string, signature: string | null, secret: string): Promise<boolean> {
  if (!signature || !secret) return false
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const mac = new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(body)))
  const expected = btoa(String.fromCharCode(...mac))
  if (expected.length !== signature.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i)
  return diff === 0
}

export type LineEvent = { type: string, timestamp: number, source?: { type: string, userId?: string }, message?: { type: string, text?: string } }

export function preview(m: LineEvent['message']): string {
  if (!m) return ''
  if (m.type === 'text') return (m.text || '').slice(0, 300)
  return ({ image: '[รูปภาพ]', sticker: '[สติกเกอร์]', video: '[วิดีโอ]', audio: '[เสียง]', file: '[ไฟล์]', location: '[ตำแหน่ง]' } as Record<string, string>)[m.type] || `[${m.type}]`
}
