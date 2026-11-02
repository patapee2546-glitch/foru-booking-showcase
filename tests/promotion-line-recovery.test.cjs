const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function fixture({tokens=true,linkFails=false,after='ok'}={}){
 const calls=[];let linked=false;
 const error=message=>({data:null,error:{context:{json:async()=>({message})}}});
 const client={auth:{getSession:async()=>({data:{session:{user:{id:'browser-a'}}}})},functions:{invoke:async(name,{body})=>{
  calls.push({name,body});
  if(name==='link-line-customer'){
   if(linkFails)return error('line_friend_required');
   linked=true;return {data:{linked:true}};
  }
  if(!linked||after==='LINE_FRIEND_REQUIRED')return error('LINE_FRIEND_REQUIRED');
  if(after!=='ok')return error(after);
  return {data:{valid:true,code:body.data.code}};
 }}};
 const root={DEMO_CONFIG:{},liff:tokens?{isLoggedIn:()=>true,getIDToken:()=> 'verified-id-token',getAccessToken:()=> 'verified-access-token'}:undefined};root.window=root;
 vm.runInNewContext(fs.readFileSync('web/demo-supabase.js','utf8'),root);
 root.DemoData.configure({client});return {api:root.DemoData,calls};
}
(async()=>{
 const good=fixture();assert.equal((await good.api.promotion('check-code',{code:'LPABC123'})).valid,true);
 assert.deepEqual(good.calls.map(x=>x.name),['promotion','link-line-customer','promotion']);
 assert.deepEqual(JSON.parse(JSON.stringify(good.calls[1].body)),{idToken:'verified-id-token',accessToken:'verified-access-token'});
 for(const options of [{tokens:false},{linkFails:true},{after:'LINE_FRIEND_REQUIRED'}]){
  const f=fixture(options);await assert.rejects(()=>f.api.promotion('check-code',{code:'LPABC123'}));
  assert.ok(f.calls.length<=3,'recovery is bounded and cannot bypass LINE verification');
 }
 const self=fixture({after:'PROMO_SELF'});await assert.rejects(()=>self.api.promotion('check-code',{code:'OWN'}),/ตัวเอง/);
 assert.equal(self.calls.length,3,'business rejection is preserved after restoring LINE');
 console.log('PASS promotion restores moved LINE link once using server verification');
})().catch(error=>{console.error(error);process.exitCode=1;});
