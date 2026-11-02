import {validateAction} from './core.ts'
Deno.test('campaign restart is owner only',()=>{
if(validateAction({action:'campaign-restart',data:{campaignId:'x'}},true).action!=='campaign-restart')throw Error('Restart unavailable');
if(validateAction({action:'revoke-award',data:{bookingId:'x'}},true).action!=='revoke-award')throw Error('Award revoke unavailable');
if(validateAction({action:'hide-award',data:{bookingId:'x'}},true).action!=='hide-award')throw Error('Award hide unavailable');
 let denied=false;try{validateAction({action:'campaign-restart',owner:true},false)}catch(e){denied=e instanceof Error&&e.message==='OWNER_REQUIRED'}
 if(!denied)throw Error('Customer can restart');
 let hideDenied=false;try{validateAction({action:'hide-award',data:{bookingId:'x'}},false)}catch(e){hideDenied=e instanceof Error&&e.message==='OWNER_REQUIRED'}
 if(!hideDenied)throw Error('Customer can hide merchant award history');
})
Deno.test('request body cannot forge owner authorization',()=>{
 let rejected=false;
 try{validateAction({action:'slot-type',owner:true,data:{special:true,p_owner:true,owner:true}},false)}catch(e){rejected=e instanceof Error&&e.message==='OWNER_REQUIRED'}
 if(!rejected)throw Error('Forged owner accepted');
})
Deno.test('inline slot change requires owner',()=>{
 if(validateAction({action:'slot-type',data:{special:true}},true).action!=='slot-type')throw Error('Missing inline action');
 let rejected=false;try{validateAction({action:'slot-type'},false)}catch(e){rejected=e instanceof Error&&e.message==='OWNER_REQUIRED'}
 if(!rejected)throw Error('Customer changed slot type');
})
Deno.test('customer cannot create campaigns or settle bills',()=>{
 for(const action of ['campaign-create','campaign-close','owner-status','quote','settle']){
  let rejected=false;try{validateAction({action},false)}catch{rejected=true}
  if(!rejected)throw Error('Owner action allowed: '+action)
 }
})
Deno.test('known customer action accepted, unknown rejected',()=>{
 for(const action of ['spin','check-code','hide-code'])if(validateAction({action,data:{campaignId:'x'}},false).action!==action)throw Error(action);
 if(validateAction({action:'hide-code',data:{code:'LP123'}},true).action!=='hide-code')throw Error('Owner cannot hide code');
 let reserveRejected=false;try{validateAction({action:'reserve'},false)}catch{reserveRejected=true}
 if(!reserveRejected)throw Error('Pre-slip reservation still allowed');
 let rejected=false;try{validateAction({action:'grant-credit'},true)}catch{rejected=true}
 if(!rejected)throw Error('Unknown action allowed')
})
