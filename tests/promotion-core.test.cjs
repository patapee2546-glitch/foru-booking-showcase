const assert=require('node:assert/strict');
const {
  quote,attemptState,wheelAngle,visibleCampaigns,promotionError,acceptReferral,createTonePlayer,selectionSoldOut
}=require('../web/promotion-core.js');
assert.deepEqual(quote({subtotal:60000,percent:10,deposit:15000}),{discount:5000,amountDue:40000,overpayment:0});
assert.deepEqual(quote({subtotal:30000,percent:5,deposit:15000}),{discount:1500,amountDue:13500,overpayment:0});
assert.deepEqual(quote({subtotal:10000,flat:5000,deposit:15000}),{discount:5000,amountDue:0,overpayment:10000});
assert.throws(()=>quote({subtotal:-1}));
assert.throws(()=>quote({subtotal:12.5}));
assert.equal(attemptState({status:'held',expires_at:'2026-09-09T00:05:00Z'},Date.parse('2026-09-09T00:05:00Z')),'expired');
assert.equal(attemptState({status:'confirmed',expires_at:'2026-09-09T00:05:00Z'},Date.parse('2026-09-09T00:06:00Z')),'confirmed');
assert.equal(attemptState({status:'confirmed',booking_status:'cancelled'}),'cancelled');

assert.deepEqual(wheelAngle(5),{stop:-60,spin:1380,counter:60});
assert.deepEqual(wheelAngle(10),{stop:-180,spin:1260,counter:180});
assert.deepEqual(wheelAngle(15),{stop:-300,spin:1140,counter:300});
assert.throws(()=>wheelAngle(20),/INVALID_PERCENT/);

const campaigns=[
  {id:'empty-active',active:true,attempt:null},
  {id:'revealed',active:false,attempt:{status:'confirmed',percent:10,canSpin:false}},
  {id:'ready',active:false,attempt:{status:'confirmed',percent:null,canSpin:true}},
  {id:'cancelled',active:false,attempt:{status:'confirmed',percent:15,booking_status:'cancelled'}}
];
assert.deepEqual(visibleCampaigns(campaigns).map(x=>x.id),['ready','empty-active'],
  'an old revealed result must not appear above a newly restarted active campaign');
assert.deepEqual(visibleCampaigns([campaigns[1]]).map(x=>x.id),['revealed'],
  'the customer can still reopen the saved result when there is no newer active campaign');

const trackedSlot={date:'2026-10-30',start:'10:00'};
const beforeSellOut=[{active:true,slots:[{date:'2026-10-30',start:'10:00:00'}]}];
assert.equal(selectionSoldOut(beforeSellOut,[],trackedSlot),true,'customer filling a special slot must be told when the third award closes it');
assert.equal(selectionSoldOut(beforeSellOut,beforeSellOut,trackedSlot),false);
assert.equal(selectionSoldOut(beforeSellOut,[],null),false);

assert.equal(promotionError({name:'PROMO_SELF'}),'ไม่สามารถใช้รหัสแนะนำของตัวเองได้ค่ะ');
assert.equal(promotionError({message:'PROMO_CODE_USED'}),'รหัสแนะนำนี้ถูกใช้ไปแล้วค่ะ');
assert.equal(promotionError({message:'offline'}),'offline');

const referralInput={value:'demo-ab12'};
assert.equal(acceptReferral(referralInput,'DEMO-AB12'),'DEMO-AB12');
assert.equal(referralInput.value,'DEMO-AB12');

let contextCount=0,resumeCount=0,contexts=[];
class FakeAudioContext{
  constructor(){contextCount++;this.currentTime=0;this.state='running';this.destination={};contexts.push(this);}
  createOscillator(){return {frequency:{value:0},connect(){return this;},start(){},stop(){}};}
  createGain(){return {gain:{setValueAtTime(){},exponentialRampToValueAtTime(){}},connect(){return this;}};}
  resume(){resumeCount++;this.state='running';return Promise.resolve();}
}
const tone=createTonePlayer(FakeAudioContext);
tone('spin');
contexts[0].state='suspended';
tone('success');
assert.equal(contextCount,1);
assert.equal(resumeCount,1);
console.log('Promotion post-slip behavior: passed');
