export class LinkCustomerError extends Error {
  constructor(public readonly code: string, public readonly status: number) {
    super(code)
    this.name = 'LinkCustomerError'
  }
}

type LinkInput = { idToken?: string; accessToken?: string }
type LinkConfig = { channelId: string }
type LinkArgs = { customerId: string; lineUserId: string; verifiedAt: string }
type LinkDependencies = {
  verifyIdToken(idToken: string, channelId: string): Promise<{ lineUserId: string }>
  verifyAccess(accessToken: string, channelId: string, expectedLineUserId: string): Promise<{ friend: boolean }>
  linkCustomer(args: LinkArgs): Promise<void>
}

export async function linkLineCustomer(
  input: LinkInput,
  customerId: string,
  config: LinkConfig,
  dependencies: LinkDependencies,
): Promise<{ linked: true }> {
  const idToken = String(input.idToken || '').trim()
  const accessToken = String(input.accessToken || '').trim()
  if (!idToken || !accessToken || !customerId || !config.channelId) {
    throw new LinkCustomerError('invalid_request', 400)
  }

  const verified = await dependencies.verifyIdToken(idToken, config.channelId)
  const access = await dependencies.verifyAccess(accessToken, config.channelId, verified.lineUserId)
  if (!access.friend) throw new LinkCustomerError('line_friend_required', 409)

  await dependencies.linkCustomer({
    customerId,
    lineUserId: verified.lineUserId,
    verifiedAt: new Date().toISOString(),
  })
  return { linked: true }
}
