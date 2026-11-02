const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('web/promotion-ui.js','utf8');
const document={getElementById:id=>id==='merchantApp'?{}:null,readyState:'loading',addEventListener(){}};
const context={window:{},document,PromotionCore:require('../web/promotion-core.js')};
vm.createContext(context);
vm.runInContext(source.replace(' root.PromotionUI=',` root.qa={show:(data,p)=>{cache=data;panel=p;render();},click}; root.PromotionUI=`),context);
const statusMessage={textContent:''};
const panel={innerHTML:'',querySelectorAll:()=>[],querySelector:selector=>selector==='[data-promo-message]'?statusMessage:null};
context.window.qa.show({campaigns:[],awards:[
 {bookingId:'active-booking',customerName:'Din',percent:5,status:'approved'},
 {bookingId:'cancelled-booking',customerName:'May',percent:10,status:'cancelled'},
],referrals:[]},panel);
assert.match(panel.innerHTML,/data-promo-revoke="active-booking"/);
assert.doesNotMatch(panel.innerHTML,/data-promo-revoke="cancelled-booking"/);
assert.match(panel.innerHTML,/data-promo-hide-award="cancelled-booking"/,'cancelled award can be dismissed from merchant history');
assert.doesNotMatch(panel.innerHTML,/data-promo-hide-award="active-booking"/,'active award cannot be dismissed');

async function verifyClick(){
 const calls=[];context.DemoData={promotion:async(action,data)=>calls.push({action,data})};
 context.confirm=()=>true;context.refresh=async()=>{};
 // Exercise the real click handler by evaluating its function with closure dependencies.
 await context.window.qa.click({target:{closest:()=>({dataset:{promoRevoke:'active-booking'},isConnected:true,disabled:false})}});
 assert.equal(calls[0]?.action,'revoke-award');assert.equal(calls[0]?.data?.bookingId,'active-booking');
 calls.length=0;
 await context.window.qa.click({target:{closest:()=>({dataset:{promoHideAward:'cancelled-booking'},isConnected:true,disabled:false})}});
 assert.equal(calls[0]?.action,'hide-award');assert.equal(calls[0]?.data?.bookingId,'cancelled-booking');
}
verifyClick().then(()=>console.log('PASS owner can cancel an unused promotion award')).catch(e=>{console.error(e);process.exitCode=1});
