(function(root){
  'use strict';
  function quote({subtotal,percent=0,flat=0,deposit=15000}){
    if(![subtotal,percent,flat,deposit].every(Number.isSafeInteger)||subtotal<0||subtotal>100000000||deposit<0||flat<0||![0,5,10,15].includes(percent)||percent&&flat)throw Error('INVALID_AMOUNT');
    const discount=Math.min(subtotal,5000,percent?Math.floor(subtotal*percent/100):flat);
    const balance=subtotal-discount-deposit;
    return {discount,amountDue:Math.max(0,balance),overpayment:Math.max(0,-balance)};
  }
  function attemptState(attempt,now=Date.now()){
    if(!attempt)return 'eligible';
    if(attempt.booking_status==='cancelled')return 'cancelled';
    return attempt.status==='held'&&Date.parse(attempt.expires_at)<=now?'expired':attempt.status;
  }
  function wheelAngle(percent){
    const center={5:60,10:180,15:300}[percent];
    if(center===undefined)throw Error('INVALID_PERCENT');
    return {stop:-center,spin:1440-center,counter:center};
  }
  function visibleCampaigns(campaigns){
    const list=campaigns||[];
    const hasActive=list.some(c=>c.active===true);
    return list.filter(c=>{
      const state=attemptState(c.attempt);
      return state!=='cancelled'&&(c.active||c.attempt?.canSpin||(!hasActive&&c.attempt?.percent));
    }).sort((a,b)=>Number(Boolean(b.attempt?.canSpin))-Number(Boolean(a.attempt?.canSpin))||Number(Boolean(b.attempt?.percent))-Number(Boolean(a.attempt?.percent)));
  }
  function promotionError(err){
    const messages={
      PROMO_CODE:'ไม่พบรหัสแนะนำนี้ หรือรหัสไม่พร้อมใช้งานค่ะ',
      PROMO_SELF:'ไม่สามารถใช้รหัสแนะนำของตัวเองได้ค่ะ',
      PROMO_CODE_USED:'รหัสแนะนำนี้ถูกใช้ไปแล้วค่ะ',
      PROMO_NEW_ONLY:'รหัสแนะนำใช้ได้สำหรับลูกค้าใหม่เท่านั้นค่ะ'
    };
    return messages[err?.name]||messages[err?.code]||messages[err?.message]||err?.message||'ลองใหม่อีกครั้งค่ะ';
  }
  function acceptReferral(input,serverCode){
    const code=String(serverCode||'').trim();
    if(!input||!code)throw Error('INVALID_PROMO_CODE');
    input.value=code;
    return code;
  }
  function createTonePlayer(AudioContext){
    let context=null;
    return function play(kind){
      try{
        if(!AudioContext)return;
        if(!context)context=new AudioContext();
        if(context.state==='suspended')context.resume()?.catch?.(()=>{});
        const notes=kind==='success'?[523,659,784]:[330,440,550];
        notes.forEach((frequency,index)=>{
          const oscillator=context.createOscillator(),gain=context.createGain(),start=context.currentTime+index*.09;
          oscillator.frequency.value=frequency;
          gain.gain.setValueAtTime(.0001,start);
          gain.gain.exponentialRampToValueAtTime(.08,start+.02);
          gain.gain.exponentialRampToValueAtTime(.0001,start+.16);
          oscillator.connect(gain);gain.connect(context.destination);
          oscillator.start(start);oscillator.stop(start+.17);
        });
      }catch(_err){}
    };
  }
  function isSpecialSlot(campaigns,date,start){
    return (campaigns||[]).some(c=>c.active===true&&(c.slots||[]).some(s=>s.date===date&&String(s.start).slice(0,5)===String(start).slice(0,5)));
  }
  function selectionSoldOut(previousCampaigns,currentCampaigns,selection){
    if(!selection)return false;
    return isSpecialSlot(previousCampaigns,selection.date,selection.start)&&!isSpecialSlot(currentCampaigns,selection.date,selection.start);
  }
  const api={quote,attemptState,isSpecialSlot,selectionSoldOut,wheelAngle,visibleCampaigns,promotionError,acceptReferral,createTonePlayer};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  else root.PromotionCore=api;
})(typeof window!=='undefined'?window:globalThis);
