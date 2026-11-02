export class CreateBookingError extends Error {
  constructor(public readonly code: string, public readonly status: number) {
    super(code)
    this.name = 'CreateBookingError'
  }
}

export type CreateBookingInput = {
  id?: string
  date?: string
  start?: string
  name?: string
  phone?: string
  removalService?: string
  designImagePath?: string | null
  lineAccessToken?: string
  benefit?: Record<string,unknown> | null
}

export type PendingBookingArgs = {
  customerId: string
  bookingId: string
  date: string
  start: string
  name: string
  phone: string
  removalService: string
  designImagePath: string | null
  benefit?: Record<string,unknown> | null
}

type Dependencies = {
  loadLineLink(customerId: string): Promise<{ lineUserId: string } | null>
  verifyAccess(accessToken: string, channelId: string, lineUserId: string): Promise<{ friend: boolean }>
  insertPendingBooking(args: PendingBookingArgs): Promise<Record<string, unknown>>
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const DATE = /^\d{4}-\d{2}-\d{2}$/
const BASE_SLOTS = new Set(['10:00', '13:30', '17:00', '20:00'])
const TUESDAY_SLOTS = new Set(['15:00', '19:00'])

function validSlot(date: string, start: string): boolean {
  if (BASE_SLOTS.has(start)) return true
  if (!TUESDAY_SLOTS.has(start)) return false
  return new Date(`${date}T00:00:00Z`).getUTCDay() === 2
}

export async function createBooking(
  input: CreateBookingInput,
  customerId: string,
  config: { channelId: string },
  dependencies: Dependencies,
): Promise<Record<string, unknown>> {
  const bookingId = String(input.id || '').trim()
  const date = String(input.date || '').trim()
  const start = String(input.start || '').slice(0, 5)
  const name = String(input.name || '').trim()
  const phone = String(input.phone || '').replace(/\D/g, '')
  const removalService = String(input.removalService || '')
  const lineAccessToken = String(input.lineAccessToken || '').trim()
  const designImagePath = input.designImagePath ? String(input.designImagePath).trim() : null

  if (!UUID.test(bookingId) || !DATE.test(date) || !name || name.length > 100 || !/^\d{9,10}$/.test(phone)) {
    throw new CreateBookingError('invalid_request', 400)
  }
  if (!validSlot(date, start)) throw new CreateBookingError('invalid_slot', 400)
  // service keys live in demo_services (owner-editable); the booking FK rejects unknown keys
  if (!/^[a-z0-9_-]{1,40}$/.test(removalService)) throw new CreateBookingError('invalid_removal', 400)
  if (designImagePath && !designImagePath.startsWith(`${customerId}/${bookingId}/`)) {
    throw new CreateBookingError('invalid_design_image', 400)
  }
  if (!lineAccessToken || !config.channelId) throw new CreateBookingError('line_friend_required', 409)

  const link = await dependencies.loadLineLink(customerId)
  if (!link) throw new CreateBookingError('line_friend_required', 409)
  const access = await dependencies.verifyAccess(lineAccessToken, config.channelId, link.lineUserId)
  if (!access.friend) throw new CreateBookingError('line_friend_required', 409)

  return dependencies.insertPendingBooking({
    customerId,
    bookingId,
    date,
    start: `${start}:00`,
    name,
    phone,
    removalService,
    designImagePath,
    ...(input.benefit ? {benefit:input.benefit} : {}),
  })
}
