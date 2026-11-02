export function validateAction(body:unknown,owner:boolean):{action:string;data:Record<string,unknown>}{
  const input=body as {action?:unknown;data?:unknown}|null
  const action=typeof input?.action==='string'?input.action:''
  const customer=['status','spin','check-code','hide-code']; const merchant=['owner-status','campaign-create','campaign-close','campaign-restart','revoke-award','hide-award','slot-type','quote','settle'];
  if(!customer.includes(action)&&!merchant.includes(action))throw Error('PROMO_ACTION')
  if(merchant.includes(action)&&!owner)throw Error('OWNER_REQUIRED')
  const data=input?.data??{}
  if(typeof data!=='object'||Array.isArray(data)||data===null)throw Error('PROMO_INVALID')
  return {action,data:data as Record<string,unknown>}
}
