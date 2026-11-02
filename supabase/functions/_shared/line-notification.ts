import { LineApiError, pushLineText } from './line-messaging.ts'

export type NotificationType = 'booking_confirmed' | 'appointment_reminder' | 'owner_booking_confirmed' | 'owner_booking_cancelled'
  | 'appointment_reminder_day' | 'booking_cancelled_by_shop' | 'owner_booking_rescheduled' | 'review_request' | 'rebook_nudge' | 'waitlist_open' | 'owner_appointment_reminder' | 'owner_slip_failed'
export type LineFailure = 'retryable' | 'permanent'

export type Appointment = {
  customer_name?: string
  customer_phone?: string
  is_special?: boolean
  slot_date: string
  start_time: string
  end_time: string
  slip_check_message?: string
}

export type NotificationJob = {
  id: string
  booking_id: string
  recipient_line_user_id: string
  notification_type: NotificationType
}

type QueryResult = { data: unknown; error: unknown }
type AdminClient = {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): { maybeSingle(): Promise<QueryResult> }
    }
  }
}

type PushText = (
  lineUserId: string,
  text: string,
  channelAccessToken: string,
  retryKey: string,
) => Promise<void>

const THAI_MONTHS = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
]

function cleanTime(value: string): string {
  return String(value || '').slice(0, 5)
}

function thaiDate(value: string): string {
  const [year, month, day] = value.split('-').map(Number)
  if (!year || !month || !day || !THAI_MONTHS[month - 1]) throw new Error('invalid_appointment_date')
  return `${day} ${THAI_MONTHS[month - 1]} ${year + 543}`
}

export function formatNotification(type: NotificationType, appointment: Appointment, links: { review?: string, booking?: string } = {}): string {
  const period = `${cleanTime(appointment.start_time)}–${cleanTime(appointment.end_time)}`
  const special = appointment.is_special ? '\n✨ รอบพิเศษ' : ''
  if (type === 'owner_booking_cancelled') {
    return `❌ สถานะ: ยกเลิกคิว\nลูกค้า: ${appointment.customer_name || 'ไม่ระบุชื่อ'}\nวันที่ ${thaiDate(appointment.slot_date)}${special}\nเวลาเดิม ${period}\nดูรายละเอียด: https://demo-nails.example.com/merchant.html`
  }
  if (type === 'owner_booking_confirmed') {
    return `มีการจองใหม่ 💅\nลูกค้า: ${appointment.customer_name || 'ไม่ระบุชื่อ'}\nเบอร์โทร: ${appointment.customer_phone?.trim() || 'ไม่ระบุ'}\nวันที่ ${thaiDate(appointment.slot_date)}${special}\nเวลา ${period}\nแนบสลิปแล้ว\nดูรายละเอียด: https://demo-nails.example.com/merchant.html`
  }
  if (type === 'owner_slip_failed') {
    return `⚠️ สลิปไม่ผ่านการตรวจอัตโนมัติ\nเหตุผล: ${appointment.slip_check_message || 'ไม่ระบุ'}\nลูกค้า: ${appointment.customer_name || 'ไม่ระบุชื่อ'}\nเบอร์โทร: ${appointment.customer_phone?.trim() || 'ไม่ระบุ'}\nวันที่ ${thaiDate(appointment.slot_date)}${special}\nเวลา ${period}\nคิวยังอยู่ · ตรวจสลิปแล้วตัดสินใจในหลังบ้าน: https://demo-nails.example.com/merchant.html`
  }
  if (type === 'owner_appointment_reminder') {
    return `⏰ อีก 1 ชม. ถึงคิว\nลูกค้า: ${appointment.customer_name || 'ไม่ระบุชื่อ'}\nเบอร์โทร: ${appointment.customer_phone?.trim() || 'ไม่ระบุ'}\nวันที่ ${thaiDate(appointment.slot_date)}${special}\nเวลา ${period}\nดูรายละเอียด: https://demo-nails.example.com/merchant.html`
  }
  if (type === 'owner_booking_rescheduled') {
    return `🔁 ลูกค้าเลื่อนคิว\nลูกค้า: ${appointment.customer_name || 'ไม่ระบุชื่อ'}\nวันที่ใหม่ ${thaiDate(appointment.slot_date)}${special}\nเวลาใหม่ ${period}\nดูรายละเอียด: https://demo-nails.example.com/merchant.html`
  }
  if (type === 'booking_cancelled_by_shop') {
    return `ขออภัยค่ะ ทางร้านยกเลิกคิวของคุณ\nวันที่ ${thaiDate(appointment.slot_date)}\nเวลา ${period}\nทางร้านจะติดต่อเรื่องมัดจำให้นะคะ หากมีคำถามทักแชทร้านได้เลยค่ะ`
  }
  if (type === 'appointment_reminder_day') {
    return `พรุ่งนี้มีนัดทำเล็บที่ Demo Nails นะคะ 💅${special}\nวันที่ ${thaiDate(appointment.slot_date)}\nเวลา ${period}\nถ้าติดธุระ เลื่อนหรือยกเลิกคิวในหน้าจองได้เลยค่ะ`
  }
  if (type === 'review_request') {
    return `ขอบคุณที่มาทำเล็บกับ Demo Nails นะคะ 💅\nถ้าชอบผลงาน ช่วยรีวิวร้านให้หน่อยได้ไหมคะ\n${links.review}`
  }
  if (type === 'waitlist_open') {
    return `รอบที่คุณรอว่างแล้วค่ะ 💅\nวันที่ ${thaiDate(appointment.slot_date)}\nเวลา ${period}\nใครจองและโอนมัดจำก่อนได้คิวก่อนนะคะ${links.booking ? `\n${links.booking}` : ''}`
  }
  if (type === 'rebook_nudge') {
    return `ถึงเวลาเติมเล็บแล้วนะคะ 💅\nทำเล็บครั้งล่าสุดผ่านมา 3 สัปดาห์แล้ว จองรอบถัดไปได้เลยค่ะ${links.booking ? `\n${links.booking}` : ''}`
  }
  if (type === 'booking_confirmed') {
    return `ยืนยันคิว Demo Nails เรียบร้อยแล้ว 💅\nวันที่ ${thaiDate(appointment.slot_date)}${special}\nเวลา ${period}\nกรุณามาถึงตามเวลานัดค่ะ`
  }
  return `อีก 1 ชั่วโมงถึงเวลานัดทำเล็บของคุณ 💅${special}\nวันนี้ เวลา ${period}\nกรุณาเดินทางมาให้ตรงเวลานะคะ`
}

export function classifyLineFailure(status: number): LineFailure {
  return status === 408 || status === 429 || status >= 500 ? 'retryable' : 'permanent'
}

export function classifyLineError(error: unknown): LineFailure {
  if (error instanceof LineApiError) return classifyLineFailure(error.status)
  return 'retryable'
}

export async function sendNotificationJob(
  admin: AdminClient,
  job: NotificationJob,
  env: { channelAccessToken: string, reviewUrl?: string, bookingUrl?: string },
  sendText: PushText = pushLineText,
): Promise<'sent' | 'retryable' | 'permanent' | 'cancelled'> {
  const result = await admin
    .from('demo_bookings')
    .select('id,status,attendance,customer_name,customer_phone,slip_check_message,slot_date,start_time,demo_slots!demo_bookings_slot_fk(end_time),demo_booking_promo_candidates(campaign_id)')
    .eq('id', job.booking_id)
    .maybeSingle()

  if (result.error) return 'retryable'
  const booking = result.data as Record<string, unknown> | null
  const requiredStatus = ['owner_booking_cancelled', 'booking_cancelled_by_shop', 'waitlist_open'].includes(job.notification_type) ? 'cancelled' : 'approved'
  if (!booking || booking.status !== requiredStatus) return 'cancelled'
  const followUp = job.notification_type === 'review_request' || job.notification_type === 'rebook_nudge'
  if (followUp && booking.attendance === 'no_show') return 'cancelled'
  if (job.notification_type === 'review_request' && !env.reviewUrl) return 'cancelled'

  const relation = Array.isArray(booking.demo_slots) ? booking.demo_slots[0] : booking.demo_slots
  const slot = relation as Record<string, unknown> | undefined
  const promoRelation = Array.isArray(booking.demo_booking_promo_candidates)
    ? booking.demo_booking_promo_candidates[0]
    : booking.demo_booking_promo_candidates
  if (
    typeof booking.slot_date !== 'string' ||
    typeof booking.start_time !== 'string' ||
    typeof slot?.end_time !== 'string' ||
    !env.channelAccessToken
  ) return 'permanent'

  const text = formatNotification(job.notification_type, {
    customer_name: typeof booking.customer_name === 'string' ? booking.customer_name : undefined,
    customer_phone: typeof booking.customer_phone === 'string' ? booking.customer_phone : undefined,
    slip_check_message: typeof booking.slip_check_message === 'string' ? booking.slip_check_message : undefined,
    is_special: Boolean(promoRelation),
    slot_date: booking.slot_date,
    start_time: booking.start_time,
    end_time: slot.end_time,
  }, { review: env.reviewUrl, booking: env.bookingUrl })
  try {
    await sendText(job.recipient_line_user_id, text, env.channelAccessToken, job.id)
    return 'sent'
  } catch (error) {
    return classifyLineError(error)
  }
}
