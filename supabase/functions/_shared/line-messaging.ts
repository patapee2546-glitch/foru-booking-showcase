const VERIFY_TOKEN_URL = 'https://api.line.me/oauth2/v2.1/verify'
const LOGIN_PROFILE_URL = 'https://api.line.me/v2/profile'
const FRIENDSHIP_URL = 'https://api.line.me/friendship/v1/status'
const PUSH_URL = 'https://api.line.me/v2/bot/message/push'

export class LineApiError extends Error {
  constructor(public readonly status: number, public readonly code: string) {
    super(code)
    this.name = 'LineApiError'
  }
}

async function safeJson(response: Response): Promise<Record<string, unknown>> {
  try {
    return await response.json() as Record<string, unknown>
  } catch {
    return {}
  }
}

function bearer(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` }
}

export async function verifyLineIdToken(
  idToken: string,
  channelId: string,
  fetcher: typeof fetch = fetch,
): Promise<{ lineUserId: string }> {
  const body = new URLSearchParams({ id_token: idToken, client_id: channelId })
  const response = await fetcher(VERIFY_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  const data = await safeJson(response)
  if (!response.ok || data.aud !== channelId || typeof data.sub !== 'string') {
    throw new LineApiError(response.status || 401, 'invalid_line_id_token')
  }
  return { lineUserId: data.sub }
}

export async function verifyLineAccess(
  accessToken: string,
  channelId: string,
  expectedLineUserId: string,
  fetcher: typeof fetch = fetch,
): Promise<{ friend: boolean }> {
  const verifyUrl = `${VERIFY_TOKEN_URL}?access_token=${encodeURIComponent(accessToken)}`
  const verifyResponse = await fetcher(verifyUrl)
  const verified = await safeJson(verifyResponse)
  if (!verifyResponse.ok || verified.client_id !== channelId) {
    throw new LineApiError(verifyResponse.status || 401, 'invalid_line_access_token')
  }

  const profileResponse = await fetcher(LOGIN_PROFILE_URL, { headers: bearer(accessToken) })
  const profile = await safeJson(profileResponse)
  if (!profileResponse.ok || profile.userId !== expectedLineUserId) {
    throw new LineApiError(profileResponse.status || 401, 'line_user_mismatch')
  }

  const friendshipResponse = await fetcher(FRIENDSHIP_URL, { headers: bearer(accessToken) })
  const friendship = await safeJson(friendshipResponse)
  if (!friendshipResponse.ok) {
    throw new LineApiError(friendshipResponse.status || 502, 'line_friendship_check_failed')
  }
  return { friend: friendship.friendFlag === true }
}

export async function pushLineText(
  lineUserId: string,
  text: string,
  channelAccessToken: string,
  retryKey: string,
  fetcher: typeof fetch = fetch,
): Promise<void> {
  const response = await fetcher(PUSH_URL, {
    method: 'POST',
    headers: {
      ...bearer(channelAccessToken),
      'Content-Type': 'application/json',
      'X-Line-Retry-Key': retryKey,
    },
    body: JSON.stringify({ to: lineUserId, messages: [{ type: 'text', text }] }),
  })
  if (!response.ok) throw new LineApiError(response.status, `line_push_${response.status}`)
}
