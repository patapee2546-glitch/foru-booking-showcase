import {withSupabase} from '@supabase/server'
import {validateAction} from './core.ts'
export default {fetch:withSupabase({auth:'user'},async(req,ctx)=>{
  if(req.method!=='POST')return Response.json({message:'method_not_allowed'},{status:405})
  const claims=(ctx.userClaims??ctx.jwtClaims??{}) as {sub?:string;id?:string;app_metadata?:{role?:string}}
  const userId=claims.sub??claims.id
  const owner=((ctx.jwtClaims?.app_metadata??claims.app_metadata) as {role?:string}|undefined)?.role==='owner'
  if(!userId)return Response.json({message:'AUTH_REQUIRED'},{status:401})
  try {
    const {action,data}=validateAction(await req.json(),owner)
    if(action==='slot-type'&&(typeof data.special!=='boolean'||typeof data.date!=='string'||typeof data.start!=='string'))return Response.json({message:'PROMO_INVALID'},{status:400})
    const {data:result,error}=await (ctx.supabaseAdmin as any).rpc(action==='campaign-restart'?'demo_promo_restart_campaign':action==='revoke-award'?'demo_promo_revoke_award':action==='hide-award'?'demo_promo_hide_award':action==='hide-code'?'demo_promo_hide_code':action==='slot-type'?'demo_promo_set_slot_type':'demo_promo_action',action==='campaign-restart'?{
      p_customer:userId,p_owner:owner,p_campaign:data.campaignId,
    }:action==='revoke-award'?{
      p_customer:userId,p_owner:owner,p_booking:data.bookingId,
    }:action==='hide-award'?{
      p_customer:userId,p_owner:owner,p_booking:data.bookingId,
    }:action==='hide-code'?{
      p_customer:userId,p_owner:owner,p_code:data.code,
    }:action==='slot-type'?{
      p_owner_id:userId,p_date:data.date,p_start:data.start,p_special:data.special,p_owner:owner,
    }:{
      p_customer:userId,p_owner:owner,p_action:action,p_data:data,
    })
    if(error){
      const message=String(error.message||'').match(/\b(PROMO_[A-Z_]+|OWNER_REQUIRED|LINE_FRIEND_REQUIRED|INVALID_AMOUNT)\b/)?.[0]||'PROMO_FAILED'
      return Response.json({message},{status:message==='OWNER_REQUIRED'?403:409})
    }
    return Response.json(result)
  }catch(e){return Response.json({message:e instanceof Error&&e.message==='OWNER_REQUIRED'?'OWNER_REQUIRED':'PROMO_INVALID'},{status:400})}
})}
