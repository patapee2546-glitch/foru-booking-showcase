window.DEMO_CONFIG = {
  SUPABASE_URL: 'https://YOUR-PROJECT.supabase.co',
  SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_YOUR_KEY',
  LIFF_ID: '1234567890-DEMODEMO',
  BOOKING_URL: 'https://demo-nails.example.com/',
  LINE_OA_ADD_URL: 'https://line.me/R/ti/p/@demoshop',
  // Sponsor logos under the live note, max 2. Example: { name:'Fastwork', url:'https://fastwork.co', logo:'sponsor-fastwork.png' } (logo optional)
  SPONSORS: [],
  // Stamp card on "รายการจอง": visits needed before a free one (0 = hide the card)
  STAMP_GOAL: 5,
  STAMP_REWARD: 'รับสิทธิ์ทำเล็บฟรี 1 ครั้ง',
  // Partner coupons shown to customers with a paid booking. Example: { name:'Daily Brew', offer:'ลด 10% แสดงคิว', code:'DEMO10', url:'https://…' }
  PARTNER_COUPONS: [],
  // LINE OA free plan messages per month (used to warn before scheduling a promo)
  LINE_MONTHLY_QUOTA: 300,
  // Shop settings: change these per shop instead of editing the page code.
  // Slot times must match the demo_slots / demo_bookings check constraints in this shop's database.
  SHOP_NAME: 'Demo Nails',
  SHOP_AREA: 'ร้านตัวอย่าง กรุงเทพฯ',
  DEPOSIT: 150,
  SERVICE_QUESTION: 'บริการล้างเล็บ',
  SLOTS: [
    { name:'รอบที่ 1 · ช่วงเช้า', start:'10:00', end:'12:30' },
    { name:'รอบที่ 2 · ช่วงบ่าย', start:'13:30', end:'16:00' },
    { name:'รอบพิเศษวันอังคาร', start:'15:00', end:'17:30', days:[2] },
    { name:'รอบที่ 3 · ช่วงเย็น', start:'17:00', end:'19:30' },
    { name:'รอบพิเศษวันอังคาร', start:'19:00', end:'21:00', days:[2] },
    { name:'รอบที่ 4 · ช่วงค่ำ', start:'20:00', end:'22:30' }
  ]
};
