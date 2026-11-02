import { previousMonth, summaryText } from './core.ts'

function equal(a: unknown, b: unknown, label: string) { if (a !== b) throw new Error(`${label}: expected ${b}, got ${a}`) }

Deno.test('previous month rolls over the year in Bangkok time', () => {
  const r = previousMonth(new Date('2026-12-31T18:00:00Z')) // already Jan 1 in Bangkok
  equal(r.from, '2026-12-01', 'from'); equal(r.to, '2027-01-01', 'to'); equal(r.label, 'ธันวาคม 2569', 'label')
})

Deno.test('summary counts paid, kept deposits, no-shows and expired', () => {
  const t = summaryText([
    { status:'approved', paid_at:'x', slot_date:'2026-10-01' },
    { status:'approved', paid_at:'x', slot_date:'2026-10-02', attendance:'no_show' },
    { status:'cancelled', paid_at:'x', slot_date:'2026-10-03', refund_status:'no_refund' },
    { status:'cancelled', paid_at:'x', slot_date:'2026-10-04', refund_status:'refund_due' },
    { status:'expired', paid_at:null, slot_date:'2026-10-05' },
  ], 'ตุลาคม 2569', 150)
  for (const part of ['คิวที่ได้: 2 คิว', 'มัดจำรับผ่านระบบ: 600 บาท', 'เก็บมัดจำไว้: 1 คิว', 'ลูกค้าไม่มา: 1 คิว', 'ไม่โอน: 1 คน'])
    if (!t.includes(part)) throw new Error(`missing ${part} in ${t}`)
})
