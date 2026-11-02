export type Row = { status: string; paid_at: string | null; slot_date: string; attendance?: string | null; refund_status?: string | null; cancelled_by_role?: string | null }

const THAI_MONTHS = ['มกราคม','กุมภาพันธ์','มีนาคม','เมษายน','พฤษภาคม','มิถุนายน','กรกฎาคม','สิงหาคม','กันยายน','ตุลาคม','พฤศจิกายน','ธันวาคม']

// Previous calendar month in Bangkok time: [first day, first day of this month)
export function previousMonth(now: Date): { from: string; to: string; label: string } {
  const bkk = new Date(now.getTime() + 7 * 3600_000)
  const y = bkk.getUTCFullYear(), m = bkk.getUTCMonth()
  const py = m === 0 ? y - 1 : y, pm = m === 0 ? 11 : m - 1
  const pad = (n: number) => String(n).padStart(2, '0')
  return { from: `${py}-${pad(pm + 1)}-01`, to: `${y}-${pad(m + 1)}-01`, label: `${THAI_MONTHS[pm]} ${py + 543}` }
}

export function summaryText(rows: Row[], label: string, deposit: number): string {
  const paid = rows.filter(r => r.paid_at)
  const done = paid.filter(r => r.status === 'approved')
  const keptDeposit = paid.filter(r => r.status === 'cancelled' && r.refund_status === 'no_refund')
  const noShow = done.filter(r => r.attendance === 'no_show')
  const expired = rows.filter(r => r.status === 'expired' || r.status === 'lost')
  const money = (n: number) => n.toLocaleString('en-US')
  return [
    `📊 สรุปเดือน${label}`,
    `คิวที่ได้: ${done.length} คิว`,
    `มัดจำรับผ่านระบบ: ${money(paid.length * deposit)} บาท`,
    `ยกเลิกแต่เก็บมัดจำไว้: ${keptDeposit.length} คิว`,
    `ลูกค้าไม่มา: ${noShow.length} คิว`,
    `ระบบกรองคนจองไม่โอน: ${expired.length} คน`,
    `ดูรายละเอียด: https://demo-nails.example.com/merchant.html`,
  ].join('\n')
}
