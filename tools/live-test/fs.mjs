// Firestore REST access for the live test helpers, using the Firebase CLI login (`npx firebase-tools login`).
// Admin access: rules do not apply, so live.mjs limits every command to the test employee.
import fs from 'node:fs'; import os from 'node:os';
const cfg = JSON.parse(fs.readFileSync(os.homedir()+'/.config/configstore/firebase-tools.json'));
const P='projects/shaon-ovdot-2c10/databases/(default)/documents';
const B='https://firestore.googleapis.com/v1/'+P;
let tok;
export async function token(){ if(tok) return tok;
 const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',body:new URLSearchParams({grant_type:'refresh_token',refresh_token:cfg.tokens.refresh_token,client_id:'563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com',client_secret:'j9iVZfS8kkCEFUPaAeJV0sAi'})});
 tok=(await r.json()).access_token; return tok;}
async function call(method,url,body){const r=await fetch(url,{method,headers:{Authorization:'Bearer '+await token(),'Content-Type':'application/json'},body:body&&JSON.stringify(body)});const t=await r.text();if(!r.ok) throw new Error(method+' '+url+' '+r.status+' '+t);return t?JSON.parse(t):{};}
const dec=v=>{const k=Object.keys(v)[0];const x=v[k];if(k==='integerValue')return Number(x);if(k==='mapValue')return obj(x.fields||{});if(k==='arrayValue')return (x.values||[]).map(dec);if(k==='nullValue')return null;return x;};
const obj=f=>Object.fromEntries(Object.entries(f).map(([a,b])=>[a,dec(b)]));
export const enc=v=>v===null?{nullValue:null}:typeof v==='boolean'?{booleanValue:v}:Number.isInteger(v)?{integerValue:String(v)}:typeof v==='number'?{doubleValue:v}:Array.isArray(v)?{arrayValue:{values:v.map(enc)}}:v instanceof Date?{timestampValue:v.toISOString()}:typeof v==='object'?{mapValue:{fields:Object.fromEntries(Object.entries(v).map(([a,b])=>[a,enc(b)]))}}:{stringValue:String(v)};
const doc=d=>({_path:d.name.split('/documents/')[1],...obj(d.fields||{})});
export async function list(path){let out=[],pt='';do{const j=await call('GET',`${B}/${path}?pageSize=300${pt?'&pageToken='+pt:''}`);out.push(...(j.documents||[]).map(doc));pt=j.nextPageToken;}while(pt);return out;}
export async function get(path){try{return doc(await call('GET',`${B}/${path}`));}catch(e){if(String(e).includes(' 404 '))return null;throw e;}}
export async function set(path,data){return doc(await call('PATCH',`${B}/${path}`,{fields:Object.fromEntries(Object.entries(data).map(([a,b])=>[a,enc(b)]))}));}
export async function del(path){return call('DELETE',`${B}/${path}`);}
export async function collGroup(id){const j=await call('POST',`https://firestore.googleapis.com/v1/${P}:runQuery`,{structuredQuery:{from:[{collectionId:id,allDescendants:true}]}});return j.filter(x=>x.document).map(x=>doc(x.document));}
