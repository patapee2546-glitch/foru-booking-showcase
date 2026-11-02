const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('web/index.html','utf8');
const core={URL};core.globalThis=core;
vm.runInNewContext(fs.readFileSync('web/line-link-core.js','utf8'),core);
async function connect({friend=false,inClient=false,accept=true}={}){
 const calls=[];
 const ctx={state:{lineEnabled:true,lineLoading:false},LineLinkCore:core.LineLinkCore,renderLineLinking(){},
 window:{DEMO_CONFIG:{LIFF_ID:'id',BOOKING_URL:'https://demo-nails.example.com/'},location:{href:'https://demo-nails.example.com/',assign:u=>calls.push(['navigate',u])},
 liff:{isLoggedIn:()=>true,isInClient:()=>inClient,getFriendship:async()=>({friendFlag:friend}),requestFriendship:async()=>{calls.push(['friend']);friend=accept;},logout:()=>calls.push(['logout']),login:v=>calls.push(['login',v.redirectUri])}},
 verifyAndLinkLine:async()=>{calls.push(['verify']);ctx.state.lineLinked=friend;return friend;}};
 vm.createContext(ctx);
 vm.runInContext(html.slice(html.indexOf('  async function connectLineAccount()'),html.indexOf('\n  }',html.indexOf('  async function connectLineAccount()'))+4),ctx);
 await ctx.connectLineAccount();return {calls,state:ctx.state};
}
(async()=>{
 const external=await connect();
 assert.deepEqual(external.calls,[['logout'],['login','https://demo-nails.example.com/?line_connect=1']],'external browser must reauthorize with LINE rather than navigate to add-friend QR');
 const linked=await connect({friend:true});assert.deepEqual(linked.calls,[['verify']]);assert.equal(linked.state.lineLinked,true);
 const native=await connect({inClient:true});assert.deepEqual(native.calls,[['friend'],['verify']]);assert.equal(native.state.lineLinked,true);
 const decline=await connect({inClient:true,accept:false});assert.equal(decline.calls.some(c=>c[0]==='navigate'||c[0]==='login'),false);assert.ok(decline.state.lineError,'declining stays on booking page with actionable message');
 console.log('PASS LINE connect uses web authorization externally, native friendship in LINE, and verifies successful links');
})().catch(e=>{console.error(e);process.exitCode=1;});
