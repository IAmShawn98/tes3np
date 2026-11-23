'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const code = fs.readFileSync('game-chat/web/seek-latest-messages.js', 'utf8');
function run({jump=false, top=0, height=1000, clientHeight=200, lastId='12345', loading=false}={}) {
  let clicks=0, scrolls=0;
  const scroller={scrollHeight:height,clientHeight,scrollTop:top,parentElement:null,
    scrollTo({top}){this.scrollTop=Math.max(0,Math.min(top,height-clientHeight));scrolls++},
    dispatchEvent() {}};
  const rows=[{id:'chat-messages-10-'+lastId}];
  const list={...scroller, querySelectorAll(sel){return rows},closest(){return scroller}};
  const jumpButton={getAttribute(k){return k==='aria-label'?'Jump to Present':null},textContent:'',getClientRects(){return [{}]},click(){clicks++}};
  const document={body:{},querySelector(sel){if(sel==='[data-list-id="chat-messages"]')return list;if(sel.includes('loadingMore'))return loading?{}:null;return null},querySelectorAll(sel){return jump?[jumpButton]:[]}};
  const sandbox={document,getComputedStyle(el){return {overflowY:'auto'}},Event:class{}};
  const result=vm.runInNewContext(code,sandbox);
  return {result,clicks,scrolls};
}
assert.deepEqual(run({jump:true}).result,'jump-requested');
assert.equal(run({jump:true}).clicks,1);
assert.equal(run({top:100}).result,'seeking');
assert.equal(run({top:800,lastId:'12345'}).result,'present:12345');
assert.equal(run({top:800,loading:true}).result,'loading');
assert.equal(run({top:800,lastId:'bad'}).result,'no-message-id');
console.log('PASS: Jump to Present, scroll to bottom, stable tail ID and load guards');
