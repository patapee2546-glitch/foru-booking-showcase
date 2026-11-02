(function(root){
 'use strict';
 const owner=Boolean(document.getElementById('merchantApp'));
 const e=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const money=n=>(Number(n)/100).toLocaleString('th-TH',{minimumFractionDigits:2,maximumFractionDigits:2});
 const day=d=>new Date(d+'T12:00:00+07:00').toLocaleDateString('th-TH',{day:'numeric',month:'short',year:'numeric'});
 const label={available:'พร้อมใช้',approved:'ได้คิวแล้ว',booked:'รอมาใช้บริการและชำระครบ',completed:'ชวนสำเร็จ ได้เครดิตแล้ว',expired:'หมดอายุ',cancelled:'ยกเลิก',used:'ใช้แล้ว'};
 let panel,cache=null,selected=null,busy=false,offset=0,previous='',dialog,settleBooking=null,quoted=null,validatedCode='',trackedSelection=null,trackedSoldOut=false;
 const playTone=PromotionCore.createTonePlayer(root.AudioContext||root.webkitAudioContext);
 const autoOpenedAttempts=new Set();
 function campaigns(){return PromotionCore.visibleCampaigns(cache?.campaigns);}
  function benefit(){
  if(selected?.type==='referral'){
   const code=document.getElementById('promo-code-input')?.value.trim();
   if(!code)throw Error('กรุณากรอกรหัสลับเพื่อน');
   if(code!==validatedCode)throw Error('กรุณาตรวจสอบรหัสแนะนำก่อนจองค่ะ');
   return {type:'referral',code};
  }
  return selected;
 }
 async function refresh(force=false){
  if(!panel||busy||!root.DemoData?.isConfigured())return;
  if(owner&&document.getElementById('merchantApp')?.hidden)return;
  try{
   const data=await DemoData.promotion(owner?'owner-status':'status');
   const justSoldOut=!owner&&PromotionCore.selectionSoldOut(cache?.campaigns,data.campaigns,trackedSelection);
   offset=Date.parse(data.serverTime)-Date.now();cache=data;
   if(justSoldOut&&!trackedSoldOut){
    trackedSoldOut=true;
    document.dispatchEvent(new CustomEvent('demo:promo-sold-out',{detail:{...trackedSelection}}));
   }
   // Avoid replacing a referral code while the customer types it.
   const signature=JSON.stringify({...data,serverTime:null});
   if(force||previous!==signature){previous=signature;render();decorateSlots();}
  }catch(err){if(force)showError(err);}
 }
 function trackSlots(date,times){
  const match=(times||[]).find(start=>PromotionCore.isSpecialSlot(cache?.campaigns,date,start));
  trackedSelection=match?{date,start:match}:null;
  trackedSoldOut=false;
  document.dispatchEvent(new CustomEvent('demo:promo-availability',{detail:{soldOut:false}}));
 }
 function clearTrackedSlot(){trackedSelection=null;trackedSoldOut=false;document.dispatchEvent(new CustomEvent('demo:promo-availability',{detail:{soldOut:false}}));}
 function showError(err){const p=panel?.querySelector('[data-promo-message]');if(p)p.textContent=PromotionCore.promotionError(err);}
 function bookingPromotionHtml(id){
  if(!id)return '';
  const received=(cache?.referrals||[]).find(r=>r.redeemedBookingId&&String(r.redeemedBookingId)===String(id));
  const receivedHtml=received?`<div class="promo-reward" style="overflow-wrap:anywhere"><h4>🎁 ${received.status==='cancelled'?'ส่วนลดจากเพื่อน 50 บาท · ยกเลิกแล้ว':'ได้รับส่วนลดจากเพื่อน 50 บาท'}</h4><p>ชื่อผู้แนะนำ: <strong>${e(received.ownerName||'ไม่พบชื่อผู้แนะนำ')}</strong></p><p>ไอดี LINE ผู้แนะนำ: <code>${e(received.ownerLineUserId||'ไม่พบไอดี LINE')}</code></p><p>รหัสที่ใช้: <code>${e(received.code)}</code></p><p>สถานะรหัส: ${label[received.status]||e(received.status)}</p></div>`:'';
  const award=(cache?.awards||[]).find(a=>String(a.bookingId)===String(id));
  const referral=(cache?.referrals||[]).find(r=>String(r.sourceBookingId)===String(id));
  if(!award&&!referral)return receivedHtml;
  return receivedHtml+`<div class="promo-reward"><h4>🎡 สิทธิ์รอบพิเศษของคิวนี้</h4><p>${award?.percent?`ส่วนลดที่สุ่มได้ <strong>${e(award.percent)}%</strong> · สูงสุด 50 บาท`:award?'รอหมุนวงล้อ':''}</p>${award?.status==='cancelled'?'<p>คิวนี้ยกเลิกแล้ว</p>':''}${referral?`<p>โค้ดชวนเพื่อน: <code>${e(referral.code)}</code></p><p>สถานะโค้ด: ${label[referral.status]||e(referral.status)}</p>${referral.recipientName?`<p>ผู้ใช้โค้ด: ${e(referral.recipientName)}</p>`:''}`:'<p>ยังไม่มีโค้ดชวนเพื่อน · โค้ดจะออกหลังลูกค้าหมุนวงล้อ</p>'}</div>`;
 }
 function decorateSlots(){
  if(owner)document.querySelectorAll('[data-promo-booking]').forEach(el=>{
   el.innerHTML=bookingPromotionHtml(el.dataset.promoBooking);el.hidden=!el.innerHTML;
  });
  document.querySelectorAll('[data-promo-inline-date]').forEach(select=>{
   const special=PromotionCore.isSpecialSlot(cache?.campaigns,select.dataset.promoInlineDate,select.dataset.promoInlineStart);
   if(!select.closest('.inline-promo-controls').querySelector('[data-promo-inline-save]'))select.value=special?'special':'normal';select.disabled=!cache||busy;
   select.closest('.inline-promo-slot')?.classList.toggle('inline-promo-special',special);
  });
  document.querySelectorAll('[data-promo-slot-date]').forEach(row=>{
   const special=PromotionCore.isSpecialSlot(cache?.campaigns,row.dataset.promoSlotDate,row.dataset.promoSlotTime);
   row.classList.toggle('promo-special-slot',special);
   row.querySelectorAll('.promo-slot-hearts,.promo-slot-label').forEach(el=>el.remove());
   if(!special)return;
   const status=row.querySelector('.mobile-status');
   if(status){const hearts=document.createElement('span');hearts.className='promo-slot-hearts';hearts.setAttribute('aria-hidden','true');hearts.innerHTML='<i>♥</i><i>♥</i><i>♥</i><i>♥</i>';status.append(hearts);}
   const time=row.querySelector('.mobile-time');
   if(time){const label=document.createElement('small');label.className='promo-slot-label';label.textContent='♥ รอบพิเศษ · โปรวงล้อ';time.append(label);}
  });
 }
 async function setInlineSlot(select){
  if(!owner||busy||!cache){decorateSlots();return;}
  const special=select.value==='special',date=select.dataset.promoInlineDate,start=select.dataset.promoInlineStart;
  const message=select.closest('.inline-promo-controls').querySelector('[data-inline-promo-message]');
  busy=true;select.disabled=true;message.textContent='กำลังบันทึก…';
  try{
   await DemoData.promotion('slot-type',{date,start,special});
   select.closest('.inline-promo-controls').querySelector('[data-promo-inline-save]')?.remove();
   message.textContent=special?'บันทึกเป็นรอบพิเศษแล้ว':'บันทึกเป็นรอบธรรมดาแล้ว';
   busy=false;await refresh(true);
  }catch(err){message.textContent=err.message||'บันทึกไม่สำเร็จ';}
  finally{busy=false;decorateSlots();}
 }
 function render(){
  if(owner){
   panel.innerHTML=`<details><summary>♥ สถานะโปรรอบพิเศษ</summary><div class="promo-body"><p>เลือกรอบธรรมดา / พิเศษได้บนการ์ดเวลาในหน้าจัดการวันนั้น</p>${(cache.campaigns||[]).filter(x=>x.active).map(x=>`<p><b>${e(x.title)}</b> เหลือ ${x.remaining} จาก 3 สิทธิ์ <button data-promo-close="${e(x.id)}">ปิดโปรทุกรอบ</button></p>`).join('')||'<p>ยังไม่มีรอบพิเศษเปิดรับ</p>'}<p class="promo-small">3 คิวแรกที่จองรอบพิเศษและแนบสลิปสำเร็จจะได้หมุนคนละ 1 ครั้ง • ส่วนลดสูงสุด 50 บาท • ไม่ใช้ซ้อนกับรหัสแนะนำหรือเครดิต</p>${(cache.awards||[]).length?`<h4>รางวัลวงล้อ</h4>${cache.awards.map(a=>`<p class="promo-award-row">${e(a.customerName)} · คิว ${e(a.bookingId)} · ${a.percent?`${a.percent}%`:'รอหมุน'} · ${label[a.status]||e(a.status)} ${a.status==='cancelled'?`<small>ยกเลิกโดยร้านแล้ว</small><button class="promo-dismiss-award" data-promo-hide-award="${e(a.bookingId)}" aria-label="ซ่อนรางวัลของ ${e(a.customerName)}">×</button>`:`<button data-promo-revoke="${e(a.bookingId)}">ยกเลิกสิทธิ์</button>`}</p>`).join('')}`:''}${(cache.referrals||[]).length?`<h4>การใช้รหัสแนะนำ</h4>${cache.referrals.map(r=>`<div class="promo-reward">${['cancelled','expired'].includes(r.status)?`<button class="promo-dismiss-code" data-promo-hide-code="${e(r.code)}" aria-label="ซ่อนรหัส ${e(r.code)}">×</button>`:''}<code>${e(r.code)}</code><p>${e(r.ownerName)} → ${e(r.recipientName||'ยังไม่มีผู้ใช้')} · ${label[r.status]||e(r.status)}</p><small>คิวต้นทาง ${e(r.sourceBookingId||'-')} · คิวที่ใช้ ${e(r.redeemedBookingId||'-')}</small><details><summary>บัญชี LINE</summary><small>บัญชี LINE ผู้แนะนำ: ${e(r.ownerLineUserId||'-')}<br>บัญชี LINE ผู้ใช้: ${e(r.recipientLineUserId||'-')}</small></details></div>`).join('')}`:''}<p data-promo-message role="status"></p></div></details>`;
   panel.querySelectorAll('[data-promo-close]').forEach(close=>{
    const restart=document.createElement('button');restart.type='button';
    restart.dataset.promoRestart=close.dataset.promoClose;
    restart.textContent='รีเซ็ตสิทธิ์ · เริ่มโปรใหม่ 3 สิทธิ์';
    close.before(restart);
   });
   return;
  }
  const oldCode=document.getElementById('promo-code-input')?.value||'';
  const cards=campaigns().map(c=>renderCampaign(c)).join('');
  const ready=campaigns().filter(c=>c.attempt?.canSpin).map(c=>c.attempt.id||c.id);
  const expand=Boolean(panel.querySelector(':scope > details')?.open)||ready.some(id=>!autoOpenedAttempts.has(id));
  ready.forEach(id=>autoOpenedAttempts.add(id));
  panel.innerHTML=`<details ${expand?'open':''}><summary>🎡 Demo Secret Five · สิทธิ์พิเศษของคุณ</summary><div class="promo-body">
   ${cards||'<p>ยังไม่มีรางวัลวงล้อค่ะ จองรอบพิเศษและแนบสลิปสำเร็จเพื่อรับสิทธิ์สำหรับ 3 คิวแรก</p>'}
   ${!cache.linked?'<p>กรุณากดเพิ่มเพื่อนและเชื่อม LINE ด้านบนก่อนรับสิทธิ์</p>':''}
   <fieldset><legend>เลือกโปรก่อนจอง · ใช้ได้ 1 โปรต่อคิว</legend>
   <label><input type="radio" name="demo-benefit" value="none" ${!selected?'checked':''}> ไม่ใช้รหัสหรือเครดิต · รอบพิเศษลุ้นวงล้ออัตโนมัติ</label>
   <label><input type="radio" name="demo-benefit" value="referral" ${selected?.type==='referral'?'checked':''}> ใช้รหัสเพื่อน ลด 50 บาท (ลูกค้าใหม่)</label>
   <input id="promo-code-input" aria-label="รหัสลับเพื่อน" placeholder="กรอกรหัสลับเพื่อน" maxlength="24" value="${e(oldCode)}"><button data-promo-check-code>ตรวจสอบรหัส</button><p data-promo-code-message role="status"></p>
   ${(cache.credits||[]).filter(x=>x.status==='available').map(x=>`<label><input type="radio" name="demo-benefit" value="credit:${e(x.id)}" ${selected?.id===x.id?'checked':''}> ใช้เครดิต 50 บาท · หมดอายุ ${new Date(x.expires_at).toLocaleDateString('th-TH')}</label>`).join('')}
   </fieldset><p class="promo-small">สิทธิ์วงล้อเกิดอัตโนมัติเมื่อแนบสลิปรอบพิเศษสำเร็จสำหรับ 3 คิวแรก • คิวปกติล็อก 5 นาที มัดจำ 150 บาท • ส่วนลดจากยอดจริงสูงสุด 50 บาท • ไม่ใช้โปรซ้อนกัน</p>
   ${(cache.codes||[]).length?`<h4>รหัสลับของคุณ</h4>${cache.codes.map(r=>`<div class="promo-reward">${['cancelled','expired'].includes(r.status)?`<button class="promo-dismiss-code" data-promo-hide-code="${e(r.code)}" aria-label="ซ่อนรหัส ${e(r.code)}">×</button>`:''}<code>${e(r.code)}</code> ${['cancelled','expired'].includes(r.status)?'':`<button data-promo-copy="${e(r.code)}">คัดลอก</button> <button data-promo-share="${e(r.code)}">แชร์</button>`}<p>${label[r.status]||e(r.status)}${r.expires_at?` · หมดอายุ ${new Date(r.expires_at).toLocaleDateString('th-TH')}`:''}</p><small class="promo-referral-terms">ชวนเพื่อนมาทำ รับส่วนลด 50.- 💗<br>โค้ดใช้ได้ภายใน 14 วัน<br>เมื่อเพื่อนมาใช้บริการ รับส่วนลด 50.-<br>ใช้ได้ภายใน 60 วัน</small></div>`).join('')}`:''}
   ${(cache.credits||[]).length?`<h4>เครดิตของคุณ</h4>${cache.credits.map(r=>`<p>50 บาท · ${label[r.status]} · หมดอายุ ${new Date(r.expires_at).toLocaleDateString('th-TH')}</p>`).join('')}`:''}
   <button data-promo-refresh>รีเฟรชสิทธิ์</button><p data-promo-message role="status"></p></div></details>`;
  panel.querySelectorAll('.promo-wheel[data-percent]').forEach(setWheelResult);
 }
 function renderCampaign(c){
  const a=c.attempt,state=PromotionCore.attemptState(a,Date.now()+offset);
  if(state==='cancelled')return '';
  if(a?.canSpin)return `<article class="promo-campaign"><h3>${e(c.title)}</h3><p>แนบสลิปสำเร็จแล้ว คุณได้สิทธิ์หมุนวงล้อ 1 ครั้งค่ะ</p><div class="promo-wheel-wrap"><span class="promo-pointer" aria-hidden="true">▼</span><div class="promo-wheel" aria-label="วงล้อส่วนลด 5, 10 และ 15 เปอร์เซ็นต์"><span><b>5%</b></span><span><b>10%</b></span><span><b>15%</b></span></div></div><button class="promo-primary" data-promo-spin="${e(c.id)}">หมุนวงล้อ</button></article>`;
  if(a?.percent)return `<article class="promo-campaign promo-congrats"><h3>ยินดีด้วยค่ะ! 🎉</h3><div class="promo-wheel-wrap"><span class="promo-pointer" aria-hidden="true">▼</span><div class="promo-wheel" data-percent="${e(a.percent)}" aria-label="ผลวงล้อ ${e(a.percent)} เปอร์เซ็นต์"><span><b>5%</b></span><span><b>10%</b></span><span><b>15%</b></span></div></div><p class="promo-result">คุณได้รับส่วนลด ${e(a.percent)}% สูงสุด 50 บาท</p><p>แคปหน้าจอนี้ไว้ได้เลยค่ะ ระบบบันทึกผลกับคิวของคุณแล้ว</p></article>`;
  return c.active?`<article class="promo-campaign"><h3>${e(c.title)}</h3><p class="promo-counter">เหลือ ${e(c.remaining)} จาก 3 สิทธิ์</p><p>จองรอบพิเศษและแนบสลิปสำเร็จ แล้ววงล้อจะปรากฏที่นี่อัตโนมัติ</p></article>`:'';
 }
 function setWheelResult(wheel){const angle=PromotionCore.wheelAngle(Number(wheel.dataset.percent));wheel.style.setProperty('--wheel-stop',`${angle.stop}deg`);wheel.style.setProperty('--wheel-counter',`${angle.counter}deg`);}
 function openDialog(title,html){
  if(dialog)dialog.remove();
  dialog=document.createElement('dialog');dialog.className='promo-dialog';
  dialog.innerHTML=`<div class="promo"><h2>${e(title)}</h2>${html}<button data-promo-dismiss>ปิด</button><p data-dialog-message role="status"></p></div>`;
  document.body.append(dialog);dialog.showModal();
 }
 async function campaignDialog(){
  const today=new Date().toLocaleDateString('en-CA',{timeZone:'Asia/Bangkok'});
  openDialog('เปิดแคมเปญ 3 คิวแรก',`<label>ชื่อแคมเปญ<input id="promo-title" value="Demo Secret Five" maxlength="80"></label><label>วันทำเล็บที่ร่วมโปร<input type="date" id="promo-date" value="${today}"></label><button data-promo-load-slots>แสดงรอบว่างของวันนี้</button><div id="promo-slots"></div><p>3 คิวแรกที่จองรอบพิเศษและแนบสลิปสำเร็จได้หมุน 1 ครั้ง สุ่ม 5%, 10%, 15% เท่ากัน ลดสูงสุด 50 บาท</p><button data-promo-create>เปิดรับ 3 สิทธิ์ตอนนี้</button>`);
 }
 async function checkout(id){
  settleBooking=id;quoted=null;
  openDialog('สรุปยอดหลังทำเสร็จ',`<label>ยอดบริการจริงก่อนส่วนลด (บาท)<input id="promo-subtotal" type="number" min="0" max="1000000" step="0.01" inputmode="decimal"></label><button data-promo-quote>คำนวณส่วนลดและยอดคงเหลือ</button><div id="promo-quote"></div><button data-promo-settle disabled>ทำเสร็จและชำระครบ</button>`);
 }
 async function click(event){
  const btn=event.target.closest('button');if(!btn)return;
  const ds=btn.dataset;
  if('promoInlineSave'in ds){await setInlineSlot(btn.closest('.inline-promo-controls').querySelector('select'));return;}
  const relevant=Object.keys(ds).some(k=>k.startsWith('promo'));
  if(!relevant)return;
  if('promoDismiss'in ds){dialog.close();dialog.remove();dialog=null;return;}
  if(busy)return;busy=true;btn.disabled=true;
  try{
   if('promoSpin'in ds){
    playTone('spin');
    const result=await DemoData.promotion('spin',{campaignId:ds.promoSpin});
    busy=false;await refresh(true);busy=true;
    const wheel=panel.querySelector(`.promo-wheel[data-percent="${result.percent}"]`),angle=PromotionCore.wheelAngle(result.percent);
    if(wheel&&!(root.matchMedia?.('(prefers-reduced-motion: reduce)').matches)){
     const animation=wheel.animate([{transform:'rotate(0deg)'},{transform:`rotate(${angle.spin}deg)`}],{duration:1500,easing:'cubic-bezier(.1,.6,.2,1)'});
     wheel.querySelectorAll('b').forEach(n=>n.animate([{transform:'rotate(0deg)'},{transform:`rotate(${-angle.spin}deg)`}],{duration:1500,easing:'cubic-bezier(.1,.6,.2,1)'}));
     await animation.finished.catch(()=>{});
    }
    playTone('success');
    openDialog('ยินดีด้วยค่ะ! 🎉',`<div class="promo-win-card"><div aria-hidden="true">🩷 ✨ 🩷</div><p>คุณได้รับส่วนลด</p><strong class="promo-win-percent">${e(result.percent)}%</strong><p>สูงสุด 50 บาท ใช้หักตอนทำเล็บเสร็จ</p><p>📸 แคปหน้าจอนี้ไว้แสดงกับทางร้านนะคะ</p>${result.code?`<p>รหัสชวนเพื่อนของคุณ<br><code>${e(result.code)}</code></p>`:''}<small>ระบบบันทึกสิทธิ์แล้ว เปิดกลับมาดูรางวัลเดิมได้ค่ะ</small></div>`);
   }else if('promoRefresh'in ds){busy=false;await refresh(true);busy=true;}
   else if('promoCopy'in ds){await navigator.clipboard.writeText(ds.promoCopy);showError({message:'คัดลอกรหัสแล้วค่ะ'});}
   else if('promoShare'in ds){
    const text=`รหัสแนะนำ Demo Nails: ${ds.promoShare} ใช้ลด 50 บาทสำหรับลูกค้าใหม่`;
    if(navigator.share)await navigator.share({title:'Demo Nails',text});else{await navigator.clipboard.writeText(text);showError({message:'คัดลอกข้อความสำหรับแชร์แล้วค่ะ'});}
   }else if('promoHideCode'in ds){
    if(confirm('ซ่อนรหัสที่ยกเลิกหรือหมดอายุรายการนี้ใช่ไหม?')){
     await DemoData.promotion('hide-code',{code:ds.promoHideCode});busy=false;await refresh(true);busy=true;
    }
   }else if('promoHideAward'in ds){
    if(confirm('ซ่อนประวัติรางวัลที่ยกเลิกนี้จากหลังบ้านใช่ไหม?')){
     await DemoData.promotion('hide-award',{bookingId:ds.promoHideAward});busy=false;await refresh(true);busy=true;
    }
   }else if('promoCheckCode'in ds){
    const input=document.getElementById('promo-code-input'),code=input.value.trim();
    if(!code)throw Error('กรุณากรอกรหัสลับเพื่อน');
    const result=await DemoData.promotion('check-code',{code});
    validatedCode=PromotionCore.acceptReferral(input,result.code);selected={type:'referral'};
    panel.querySelector('[data-promo-code-message]').innerHTML=`ยินดีด้วยค่ะ! คุณได้รับส่วนลด 50 บาท จากการแนะนำของคุณ ${e(result.referrerName)}<br><small>เลือกคิวต่อได้เลย ระบบจะเริ่มล็อกคิวเมื่อยืนยันการจอง และต้องแนบสลิปภายใน 5 นาทีค่ะ</small>`;
    panel.querySelector('[name="demo-benefit"][value="referral"]').checked=true;
   }
   else if('promoNew'in ds)await campaignDialog();
   else if('promoLoadSlots'in ds){
    const date=document.getElementById('promo-date').value;
    const slots=await DemoData.listSlots(date,date);
    document.getElementById('promo-slots').innerHTML=slots.filter(s=>s.is_open&&!s.is_booked&&Date.parse(`${s.slot_date}T${s.start_time.slice(0,5)}:00+07:00`)>Date.now()).map(s=>`<label>${day(s.slot_date)} ${e(s.start_time)}–${e(s.end_time)}<select name="promo-slot-type" data-slot-id="${e(s.id)}"><option value="normal">ธรรมดา</option><option value="special">♥ พิเศษ — ร่วมโปรวงล้อ</option></select></label>`).join('')||'<p>วันนี้ไม่มีรอบว่างที่เปิดรับ</p>';
   }else if('promoCreate'in ds){
    const title=document.getElementById('promo-title').value.trim(),slots=[...document.querySelectorAll('[name="promo-slot-type"]')].filter(x=>x.value==='special').map(x=>x.dataset.slotId);
    if(!title||!slots.length)throw Error('กรุณาใส่ชื่อและเลือกรอบว่างก่อนเปิด');
    if(confirm('เปิดแคมเปญนี้ให้ลูกค้ารับ 3 สิทธิ์ทันทีใช่ไหม?')){await DemoData.promotion('campaign-create',{title,slots});dialog.close();dialog.remove();dialog=null;busy=false;await refresh(true);busy=true;}
   }else if('promoRevoke'in ds){
    if(confirm('ยกเลิกส่วนลดวงล้อและโค้ดแนะนำของคิวนี้ใช่ไหม? สิทธิ์ที่ใช้หรือปิดยอดแล้วจะยกเลิกไม่ได้')){
     await DemoData.promotion('revoke-award',{bookingId:ds.promoRevoke});busy=false;await refresh(true);busy=true;
     showError({message:'ยกเลิกสิทธิ์และโค้ดแนะนำของคิวนี้แล้ว'});
    }
   }else if('promoRestart'in ds){
    if(confirm('เริ่มโปรรอบใหม่ 3 สิทธิ์สำหรับรอบเวลาที่ร่วมโปรเดิม? ส่วนลด โค้ด และเครดิตเดิมยังอยู่ ไม่ปลดคิวที่จองแล้ว')){
     await DemoData.promotion('campaign-restart',{campaignId:ds.promoRestart});
     busy=false;await refresh(true);busy=true;
     showError({message:'เริ่มโปรใหม่ 3 สิทธิ์แล้ว สิทธิ์และโค้ดเดิมยังอยู่ครบ'});
    }
   }else if('promoClose'in ds){
    if(confirm('ปิดรับสิทธิ์ใหม่? ผู้ที่แนบสลิปและได้สิทธิ์แล้วจะยังเห็นรางวัลเดิม')){await DemoData.promotion('campaign-close',{campaignId:ds.promoClose});busy=false;await refresh(true);busy=true;}
   }else if('promoCheckout'in ds)await checkout(ds.promoCheckout);
   else if('promoQuote'in ds){
    const raw=document.getElementById('promo-subtotal').value;
    if(!/^\d+(\.\d{1,2})?$/.test(raw))throw Error('กรุณากรอกยอดเงิน ทศนิยมไม่เกิน 2 ตำแหน่ง');
    const subtotal=Math.round(Number(raw)*100);
    quoted=await DemoData.promotion('quote',{bookingId:settleBooking,subtotal});
    document.getElementById('promo-quote').innerHTML=`<p>ยอดบริการ ${money(quoted.subtotal)} บาท</p><p>ส่วนลด −${money(quoted.discount)} บาท</p><p>มัดจำ −${money(quoted.deposit)} บาท</p><h3>จ่ายเพิ่ม ${money(quoted.amountDue)} บาท</h3>${quoted.overpayment?`<p>ยอดชำระเกิน ${money(quoted.overpayment)} บาท กรุณาจัดการยอดเกินก่อนยืนยัน</p>`:''}${quoted.settled?'<p>บันทึกชำระครบแล้ว</p>':''}`;
    dialog.querySelector('[data-promo-settle]').disabled=quoted.settled;
   }else if('promoSettle'in ds){
    if(!quoted||Math.round(Number(document.getElementById('promo-subtotal').value)*100)!==quoted.subtotal)throw Error('ยอดเปลี่ยน กรุณาคำนวณอีกครั้ง');
    if(confirm(`ยืนยันทำเสร็จและรับชำระเพิ่ม ${money(quoted.amountDue)} บาทครบแล้ว${quoted.overpayment?' และจัดการยอดเกินแล้ว':''}? ระบบจะให้เครดิตคนแนะนำอัตโนมัติ และไม่ให้แก้ยอดซ้ำ`)){
     await DemoData.promotion('settle',{bookingId:settleBooking,subtotal:quoted.subtotal});
     quoted.settled=true;dialog.querySelector('[data-dialog-message]').textContent='บันทึกชำระครบแล้ว เครดิตคนแนะนำจะออกให้อัตโนมัติหากคิวนี้ใช้รหัสเพื่อน';
    }
   }
  }catch(err){if(dialog)dialog.querySelector('[data-dialog-message]').textContent=err.message;else showError(err);}
  finally{busy=false;if(btn.isConnected)btn.disabled=('promoSettle'in ds)&&Boolean(quoted?.settled);}
 }
 function mount(){
  panel=document.createElement('section');panel.className='promo';panel.id='demo-promotion';
  const target=owner?document.querySelector('#merchantApp main'):document.getElementById('lineLinkCard');
  if(!target)return;
  owner?target.prepend(panel):target.after(panel);
  document.addEventListener('click',click);
  document.addEventListener('change',ev=>{
   if(ev.target.matches('[data-promo-inline-date]')){
    const controls=ev.target.closest('.inline-promo-controls');
    let save=controls.querySelector('[data-promo-inline-save]');
    if(!save){save=document.createElement('button');save.type='button';save.dataset.promoInlineSave='';controls.append(save);}
    save.textContent=ev.target.value==='special'?'บันทึกเป็นพิเศษ · เปิดโปรทันที':'บันทึกเป็นธรรมดา';
    controls.querySelector('[data-inline-promo-message]').textContent='รางวัลของผู้ที่แนบสลิปสำเร็จแล้วจะยังคงเดิม';
    return;
   }
   if(ev.target.name==='demo-benefit'){
    const v=ev.target.value;selected=v==='referral'?{type:'referral'}:v.startsWith('credit:')?{type:'credit',id:v.slice(7)}:null;
   }
   if(ev.target.id==='promo-code-input'&&ev.target.value.trim()!==validatedCode)validatedCode='';
   if(ev.target.id==='promo-date'){document.getElementById('promo-slots').replaceChildren();}
   if(ev.target.id==='promo-subtotal'&&dialog){quoted=null;dialog.querySelector('[data-promo-settle]').disabled=true;}
  });
  refresh();setInterval(()=>refresh(),15000);setInterval(()=>{if(trackedSelection&&!document.hidden)refresh();},2000);
 }
 root.PromotionUI={refresh,benefit,checkout,decorateSlots,trackSlots,clearTrackedSlot};
 document.readyState==='loading'?document.addEventListener('DOMContentLoaded',mount):mount();
})(window);
