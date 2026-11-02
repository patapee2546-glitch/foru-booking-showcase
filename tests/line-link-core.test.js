const assert = require('assert');
const fs = require('fs');
const vm = require('vm');

const context = {};
context.URL = URL;
context.globalThis = context;
vm.runInNewContext(fs.readFileSync('web/line-link-core.js', 'utf8'), context);
const Line = context.LineLinkCore;

assert.equal(Line.isEnabled({ LIFF_ID:'' }), false);
assert.equal(Line.isEnabled({ LIFF_ID:'1234567890-AbCdEf' }), true);
assert.equal(Line.canBook({ enabled:false, linked:false }), true, 'missing config must not break existing bookings');
assert.equal(Line.canBook({ enabled:true, linked:false }), false, 'configured LIFF requires a verified link');
assert.equal(Line.canBook({ enabled:true, linked:true }), true);

assert.deepEqual(Line.presentation({ enabled:true, loading:true }), {
  tone:'loading', title:'กำลังตรวจสอบ LINE…', action:'', ready:false,
});
assert.deepEqual(Line.presentation({ enabled:true, friend:false, linked:false }), {
  tone:'required', title:'เพิ่มเพื่อน LINE ร้านก่อนจองคิว', action:'เพิ่มเพื่อนและเชื่อม LINE', ready:false,
});
assert.deepEqual(Line.presentation({ enabled:true, friend:true, linked:true }), {
  tone:'ready', title:'เชื่อม LINE ร้านแล้ว พร้อมรับแจ้งเตือน', action:'', ready:true,
});

assert.deepEqual(Line.initAction({ loggedIn:false }), { type:'wait' },
  'opening the booking page in Safari must not redirect until the customer taps connect');
assert.deepEqual(Line.initAction({ loggedIn:true }), { type:'continue' });

assert.deepEqual(Line.friendshipAction({
  friend:false,
  lineOaUrl:'https://line.me/R/ti/p/@demoshop',
}), {
  type:'navigate',
  url:'https://line.me/R/ti/p/@demoshop',
}, 'Safari must navigate in the same tab because it blocks popups opened after an async friend check');
assert.deepEqual(Line.friendshipAction({ friend:true }), { type:'continue' });

assert.deepEqual(Line.loginAction({
  liffId:'1234567890-DEMODEMO',
  loggedIn:false,
  currentUrl:'https://demo-nails.example.com/',
}), {
  type:'login',
  redirectUri:'https://demo-nails.example.com/?line_connect=1',
}, 'Safari must use web login and return to Safari instead of opening the LINE app');

assert.deepEqual(Line.loginAction({
  liffId:'1234567890-DEMODEMO',
  loggedIn:false,
  currentUrl:'https://demo-nails.example.com/?line_connect=1',
}), {
  type:'login',
  redirectUri:'https://demo-nails.example.com/?line_connect=1',
}, 'LINE Login must return with the connection marker so linking continues automatically');

assert.deepEqual(Line.loginAction({
  liffId:'1234567890-DEMODEMO',
  loggedIn:false,
  currentUrl:'file:///Users/pleng/Desktop/nails_booking.html',
  webUrl:'https://demo-nails.example.com/',
}), {
  type:'navigate',
  url:'https://demo-nails.example.com/?line_connect=1',
}, 'a downloaded HTML must start login on the registered web origin so its OAuth state survives');

const liveUrl='https://demo-nails.example.com/';
assert.deepEqual(Line.loginAction({loggedIn:false,currentUrl:'https://demo-nails-old.example.com/?old=1',webUrl:liveUrl}),
 {type:'navigate',url:liveUrl+'?line_connect=1'},'an old domain must move to the registered origin before starting LINE login');
assert.deepEqual(Line.loginAction({loggedIn:false,currentUrl:liveUrl+'?foo=1#bar',webUrl:liveUrl}),
 {type:'login',redirectUri:liveUrl+'?line_connect=1'},'the current site keeps login and callback in the same browser origin');

assert.deepEqual(Line.loginAction({
  liffId:'1234567890-DEMODEMO',
  loggedIn:true,
  currentUrl:'https://demo-nails.example.com/?line_connect=1',
}), { type:'continue' });

console.log('LINE link core: passed');
