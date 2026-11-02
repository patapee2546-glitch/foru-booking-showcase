const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('web/promotion-ui.js','utf8');
const core=require('../web/promotion-core.js');

function render(owner,data){
  const document={getElementById:id=>id==='merchantApp'&&owner?{}:null,readyState:'loading',addEventListener(){},dispatchEvent(){}};
  const context={window:{},document,CustomEvent:function(){},PromotionCore:core};
  vm.createContext(context);
  vm.runInContext(source.replace(' root.PromotionUI=',` root.qa={show:(data,p)=>{cache=data;panel=p;render();}}; root.PromotionUI=`),context);
  const panel={innerHTML:'',querySelectorAll:()=>[],querySelector:()=>null};
  context.window.qa.show(data,panel);
  return panel.innerHTML;
}

const customer=render(false,{linked:true,campaigns:[],credits:[],codes:[
  {code:'LPCANCELLED',status:'cancelled'},
  {code:'LPREADY',status:'available'},
]});
assert.match(customer,/data-promo-hide-code="LPCANCELLED"/,'customer can dismiss a cancelled code');
assert.doesNotMatch(customer,/data-promo-hide-code="LPREADY"/,'customer cannot dismiss an active code');
assert.match(customer,/ชวนเพื่อนมาทำ รับส่วนลด 50\.\- 💗<br>โค้ดใช้ได้ภายใน 14 วัน<br>เมื่อเพื่อนมาใช้บริการ รับส่วนลด 50\.\-<br>ใช้ได้ภายใน 60 วัน/,'each secret code explains both 50-baht benefits and their deadlines clearly');

const merchant=render(true,{campaigns:[],awards:[],referrals:[
  {code:'LPEXPIRED',status:'expired',ownerName:'Din'},
  {code:'LPBOOKED',status:'booked',ownerName:'May'},
]});
assert.match(merchant,/data-promo-hide-code="LPEXPIRED"/,'merchant can dismiss an expired code');
assert.doesNotMatch(merchant,/data-promo-hide-code="LPBOOKED"/,'merchant cannot dismiss a booked code');
console.log('PASS cancelled and expired referral codes have safe dismiss controls');
