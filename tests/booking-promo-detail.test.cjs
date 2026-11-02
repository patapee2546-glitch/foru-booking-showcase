const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('web/promotion-ui.js','utf8');
const context={window:{},document:{getElementById:()=>null,readyState:'loading',addEventListener(){}},PromotionCore:require('../web/promotion-core.js')};
vm.createContext(context);
vm.runInContext(source.replace(' root.PromotionUI=', ' root.qa={setCache:v=>cache=v,html:id=>typeof bookingPromotionHtml==="function"?bookingPromotionHtml(id):""}; root.PromotionUI='),context);
const qa=context.window.qa;
qa.setCache({awards:[{bookingId:'b1',percent:15,status:'approved'},{bookingId:'b2',percent:null,status:'approved'}],referrals:[{sourceBookingId:'b1',code:'LP123ABC',status:'used',recipientName:'เพื่อน <script>'},{sourceBookingId:'other',code:'OTHER123',status:'available'}]});
const html=qa.html('b1');assert.match(html,/15%/);assert.match(html,/LP123ABC/);assert.match(html,/ใช้แล้ว/);assert.doesNotMatch(html,/OTHER123|<script>/);assert.match(html,/&lt;script&gt;/);
assert.match(qa.html('b2'),/รอหมุน/);assert.equal(qa.html('unrelated'),'');
console.log('PASS per-booking award, code, usage, escaping and unspun state');

// A redeemed code must appear on the recipient's booking, not only the source booking.
qa.setCache({awards:[],referrals:[
 {sourceBookingId:'source',redeemedBookingId:'recipient',code:'LPFRIEND50',status:'used',ownerName:'พิม <script>',ownerLineUserId:'Uowner123',recipientName:'ลูกค้าใหม่'},
 {sourceBookingId:'another',redeemedBookingId:'someone-else',code:'WRONGCODE',status:'used',ownerName:'คนอื่น',ownerLineUserId:'Uwrong'},
 {sourceBookingId:'unclaimed',redeemedBookingId:null,code:'UNCLAIMED',status:'available',ownerName:'ยังไม่ใช้'}
]});
const received=qa.html('recipient');
assert.match(received,/50 บาท/);
assert.match(received,/พิม &lt;script&gt;/);
assert.match(received,/Uowner123/);
assert.match(received,/LPFRIEND50/);
assert.doesNotMatch(received,/WRONGCODE|Uwrong|UNCLAIMED|<script>|รอหมุนวงล้อ/);
assert.equal(qa.html('not-booked'),'');
assert.doesNotMatch(qa.html('source'),/ได้รับส่วนลดจากเพื่อน/);
qa.setCache({referrals:[{sourceBookingId:'src',redeemedBookingId:'cancelled-recipient',code:'LPCANCEL',status:'cancelled'}]});
assert.match(qa.html('cancelled-recipient'),/ยกเลิก/);
assert.doesNotMatch(qa.html('cancelled-recipient'),/undefined|null/);
console.log('PASS recipient booking shows its referral discount and escaped referrer identity');
