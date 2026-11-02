(function (root) {
  'use strict';

  function isEnabled(config) {
    return Boolean(String(config?.LIFF_ID || '').trim());
  }

  function canBook(state) {
    return state?.enabled !== true || state?.linked === true;
  }

  function presentation(state) {
    if (state?.enabled !== true) {
      return { tone:'disabled', title:'ระบบแจ้งเตือน LINE ยังไม่เปิดใช้งาน', action:'', ready:true };
    }
    if (state?.loading) {
      return { tone:'loading', title:'กำลังตรวจสอบ LINE…', action:'', ready:false };
    }
    if (state?.friend === true && state?.linked === true) {
      return { tone:'ready', title:'เชื่อม LINE ร้านแล้ว พร้อมรับแจ้งเตือน', action:'', ready:true };
    }
    return { tone:'required', title:'เพิ่มเพื่อน LINE ร้านก่อนจองคิว', action:'เพิ่มเพื่อนและเชื่อม LINE', ready:false };
  }

  function initAction({ loggedIn }) {
    return loggedIn === true ? { type:'continue' } : { type:'wait' };
  }

  function friendshipAction({ friend, lineOaUrl }) {
    if (friend === true) return { type:'continue' };
    return { type:'navigate', url:String(lineOaUrl || 'https://line.me/R/ti/p/@demoshop') };
  }

  function loginAction({ liffId, loggedIn, currentUrl, webUrl }) {
    const current = String(currentUrl || '');
    const configured = String(webUrl || '');
    const url = /^https:\/\//i.test(configured) ? configured : current;
    const returnUrl = `${url.split('#')[0].split('?')[0]}?line_connect=1`;
    // Start OAuth on the registered site: another origin cannot recover this
    // browser's login state, and LINE rejects callbacks outside its LIFF endpoint.
    if (/^https:\/\//i.test(url) && (!/^https:\/\//i.test(current) || new URL(current).origin !== new URL(url).origin)) {
      return { type:'navigate', url:returnUrl };
    }
    if (loggedIn === true) return { type:'continue' };
    return { type:'login', redirectUri:returnUrl };
  }

  root.LineLinkCore = { isEnabled, canBook, presentation, initAction, friendshipAction, loginAction };
})(typeof globalThis !== 'undefined' ? globalThis : this);
