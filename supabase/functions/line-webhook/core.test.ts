import { preview, validSignature } from './core.ts'

async function sign(body: string, secret: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body)))))
}

Deno.test('only LINE-signed bodies are accepted', async () => {
  const body = '{"events":[]}', sig = await sign(body, 's3cret')
  if (!(await validSignature(body, sig, 's3cret'))) throw new Error('valid signature rejected')
  if (await validSignature(body + ' ', sig, 's3cret')) throw new Error('changed body accepted')
  if (await validSignature(body, sig, 'other')) throw new Error('wrong secret accepted')
  if (await validSignature(body, null, 's3cret')) throw new Error('missing signature accepted')
  if (await validSignature(body, sig, '')) throw new Error('empty secret accepted')
})

Deno.test('message previews', () => {
  if (preview({ type: 'text', text: 'จองคิวค่ะ' }) !== 'จองคิวค่ะ') throw new Error('text')
  if (preview({ type: 'image' }) !== '[รูปภาพ]') throw new Error('image')
  if (preview({ type: 'text', text: 'x'.repeat(400) }).length !== 300) throw new Error('cut')
})
