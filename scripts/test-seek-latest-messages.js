'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const code = fs.readFileSync('game-chat/web/seek-latest-messages.js', 'utf8');
const extractCode = fs.readFileSync('game-chat/web/extract-feed.js', 'utf8');
// Both packaged editable CSS and embedded fallback must preserve the attachment
// nodes and Discord's native tail-recovery control.
for (const path of ['game-chat/chat.css', 'game-chat/web/discord-source.css']) {
  const css = fs.readFileSync(path, 'utf8');
  assert.doesNotMatch(css, /\[class\*="jumpToPresentBar_"\]/);
  assert.doesNotMatch(css, /\[class\*="messageAccessories_"\]/);
}
function run({jump=false, top=0, height=1000, clientHeight=200, lastId='12345', loading=false, styledHidden=false}={}) {
  let clicks=0, scrolls=0;
  const sourceSheet={disabled:false};
  const scroller={scrollHeight:height,clientHeight,scrollTop:top,parentElement:null,
    scrollTo({top}){this.scrollTop=Math.max(0,Math.min(top,height-clientHeight));scrolls++},
    dispatchEvent() {}};
  const rows=[{id:'chat-messages-10-'+lastId}];
  const list={...scroller, querySelectorAll(sel){return rows},closest(){return scroller}};
  const jumpButton={getAttribute(k){return k==='aria-label'?'Jump to Present':null},textContent:'',getClientRects(){return styledHidden && !sourceSheet.disabled ? [] : [{}]},click(){clicks++}};
  const document={body:{},getElementById(id){return id==='tes3np-chat-style'?{sheet:sourceSheet}:null},querySelector(sel){if(sel==='[data-list-id="chat-messages"]')return list;if(sel.includes('loadingMore'))return loading?{}:null;return null},querySelectorAll(sel){return jump?[jumpButton]:[]}};
  const sandbox={document,getComputedStyle(el){return {overflowY:'auto'}},Event:class{}};
  const result=vm.runInNewContext(code,sandbox);
  return {result,clicks,scrolls,styleRestored:!sourceSheet.disabled};
}
assert.deepEqual(run({jump:true}).result,'jump-requested');
assert.equal(run({jump:true}).clicks,1);
assert.equal(run({jump:true,styledHidden:true}).clicks,1);
assert.equal(run({jump:true,styledHidden:true}).styleRestored,true);
assert.equal(run({top:100}).result,'seeking');
assert.equal(run({top:800,lastId:'12345'}).result,'present:12345');
assert.equal(run({top:800,loading:true}).result,'loading');
assert.equal(run({top:800,lastId:'bad'}).result,'no-message-id');
console.log('PASS: Jump to Present, scroll to bottom, stable tail ID and load guards');

// Image-only grouped messages retain a previously observed author by exact ID.
// A never-before-seen headerless row must not be attributed to Yagrum.
function extract(rows, state={}) {
  const node = {querySelectorAll(){return rows}};
  const document = {getElementById(){return null},querySelector(selector) {
    return selector === '[data-list-id="chat-messages"]' ? node : null;
  }};
  const result = vm.runInNewContext(extractCode, {
    document, window:state, URL, getComputedStyle() {
      return {getPropertyValue(){return ''},color:''};
    }
  });
  return JSON.parse(result);
}
function mockRow(id, user, image) {
  const username = user ? {textContent:user,closest(){return null}} : null;
  const media = image ? [{tagName:'IMG',src:image,currentSrc:image}] : [];
  return {id:'chat-messages-10-'+id,
    querySelector(selector) {
      return selector === '[class*="username_"]' ? username : null;
    },
    querySelectorAll(){return media}
  };
}
const sourceState={};
const picture='https://cdn.discordapp.com/attachments/1/2/happy.png';
let parsed=extract([mockRow(10,'Yagrum',null),mockRow(11,'',picture)],sourceState);
assert.equal(parsed[0].sourceAuthor,'Yagrum');
parsed=extract([mockRow(11,'',picture)],sourceState);
assert.equal(parsed[0].sourceAuthor,'Yagrum');
parsed=extract([mockRow(12,'',picture)],sourceState);
assert.equal(parsed[0].sourceAuthor,'');
console.log('PASS: Image-only grouped author cache and unknown-author fail-closed');
