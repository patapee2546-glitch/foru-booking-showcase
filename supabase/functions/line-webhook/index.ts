// LINE Messaging API webhook: keeps the latest message of each customer who writes to the OA,
// so the For U LINE console can list chats the shop hasn't answered yet.
import { createClient } from 'npm:@supabase/supabase-js@2.116.0'
import { validSignature, preview, type LineEvent } from './core.ts'

Deno.serve(async req => {
  if (req.method !== 'POST') return new Response('ok')
  const body = await req.text()
  if (!(await validSignature(body, req.headers.get('x-line-signature'), Deno.env.get('LINE_CHANNEL_SECRET') || ''))) {
    return new Response('bad signature', { status: 401 })
  }
  let events: LineEvent[] = []
  try { events = (JSON.parse(body).events || []) as LineEvent[] } catch { return new Response('bad json', { status: 400 }) }

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
  const token = Deno.env.get('LINE_CHANNEL_ACCESS_TOKEN') || ''
  for (const e of events) {
    const userId = e.source?.type === 'user' ? e.source.userId : undefined
    if (e.type !== 'message' || !userId) continue
    const { data: old } = await admin.from('demo_line_chats').select('display_name,picture_url,unanswered_count').eq('line_user_id', userId).maybeSingle()
    let profile = { displayName: old?.display_name ?? null, pictureUrl: old?.picture_url ?? null }
    if (!old && token) {
      const r = await fetch(`https://api.line.me/v2/bot/profile/${encodeURIComponent(userId)}`, { headers: { Authorization: `Bearer ${token}` } }).catch(() => null)
      if (r?.ok) profile = await r.json()
    }
    await admin.from('demo_line_chats').upsert({
      line_user_id: userId, display_name: profile.displayName, picture_url: profile.pictureUrl,
      last_text: preview(e.message), last_at: new Date(e.timestamp).toISOString(), unanswered_count: (old?.unanswered_count ?? 0) + 1,
    })
    // full thread for the console (text up to 5,000 chars; other types as a short label)
    await admin.from('demo_line_messages').insert({ line_user_id: userId, at: new Date(e.timestamp).toISOString(), dir: 'in',
      text: e.message?.type === 'text' ? (e.message.text || '').slice(0, 5000) : preview(e.message) })
  }
  return new Response('ok')
})
