const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('web/promotion-ui.js','utf8');
const core=require('../web/promotion-core.js');
let rendered='',details=null;
const panel={get innerHTML(){return rendered;},set innerHTML(v){rendered=v;details={open:/^<details\s+open[\s>]/.test(v)};},querySelector:()=>details,querySelectorAll:()=>[]};
const context={owner:false,panel,cache:{linked:true,campaigns:[{id:'a',active:true,remaining:5,attempt:null}]},selected:null,offset:0,autoOpenedAttempts:new Set(),
 document:{getElementById:()=>null},PromotionCore:core,e:s=>String(s),label:{}};
context.campaigns=()=>core.visibleCampaigns(context.cache.campaigns);
vm.createContext(context);
vm.runInContext(source.slice(source.indexOf(' function render(){'),source.indexOf(' function openDialog(')),context);
context.render();assert.equal(details.open,false,'active offer alone must not expand the first screen');
details.open=true;context.render();assert.equal(details.open,true,'manual expansion survives refresh');
details.open=false;context.render();assert.equal(details.open,false,'manual collapse survives refresh');
context.cache.campaigns[0].attempt={id:'award-1',canSpin:true,status:'confirmed',booking_status:'approved'};
context.render();assert.equal(details.open,true,'new post-slip award automatically expands');
details.open=false;context.render();assert.equal(details.open,false,'same award does not force reopen on polling');
context.cache.campaigns[0].attempt={id:'award-1',canSpin:false,percent:10,status:'confirmed'};
context.render();assert.equal(details.open,false,'past prize alone does not force reopen');
console.log('PASS promotion initially collapsed, manual state preserved, new award expands once');
