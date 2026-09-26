/* Zero-dependency smoke test for the browser demo's sample finance workflows. */
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const handlers = new Map();
const storage = new Map();
const elements = new Map();
function element(id) { if (!elements.has(id)) elements.set(id, {id, innerHTML:'', textContent:'', style:{}, dataset:{}, hidden:false, addEventListener(event,fn){handlers.set(`${id}:${event}`,fn);}, replaceWith(){}, focus(){}, get firstElementChild(){return null;},querySelector(){return {focus(){}};}});return elements.get(id); }
const navButtons = ['dashboard','transactions','budgets','analytics','plans','subscriptions','notes'].map(name=>({dataset:{screen:name},classList:{toggle(){}},setAttribute(){},removeAttribute(){}}));
const document = {
  getElementById: id => element(id),
  querySelectorAll: selector => selector==='#demo-navigation [data-screen]'?navButtons:[],
  addEventListener: (name,fn)=>handlers.set(name,fn),
  activeElement: {focus(){},isConnected:true},
  body:{style:{}},
};
class DemoFormData { constructor(form) {this.values=form.values||{};}get(key){return this.values[key]??null;} }
const fakeSessionStorage = {getItem:key=>storage.get(key)??null,setItem:(key,value)=>storage.set(key,String(value))};
const context = vm.createContext({document,window:{KOINLY_SITE:{},matchMedia:()=>({matches:false})},sessionStorage:fakeSessionStorage,FormData:DemoFormData,Intl,Date,Math,Number,String,Object,Array,Set,Map,JSON,Node:{TEXT_NODE:3,ELEMENT_NODE:1},console,setTimeout:()=>1,clearTimeout:()=>{},crypto:{randomUUID:()=>`uuid-${++uuid}`}});
let uuid=0;
vm.runInContext(fs.readFileSync(path.join(root,'app.js'),'utf8'),context,{filename:'app.js'});
function click(selector,dataset) {const target={dataset,hasAttribute:()=>false,closest:s=>selector===s?{dataset}:null};handlers.get('click')({target});}
function submit(id,values,extra={}){let amountNode={value:values.amount??values.price??values.limit??''};const form={id,dataset:extra,values,elements:{namedItem:()=>amountNode},reportValidity:()=>true,querySelector:()=>null};handlers.get('submit')({target:form,preventDefault(){}});}
function state(){return JSON.parse(storage.get('koinly-public-demo-v1'));}
const html=()=>element('demo-content').innerHTML;
assert.match(html(),/\$12,873\.00/,'initial dashboard balance');
click('#demo-navigation [data-screen]',{screen:'transactions'});
assert.match(html(),/Groceries/,'transactions rendered');
submit('form-transaction',{title:'A <test> transaction',type:'expense',category:'Food',amount:'20',accountId:'cash',date:new Date().toISOString().slice(0,10)});
assert.match(html(),/A &lt;test&gt; transaction/,'user-entered title escaped');
assert.equal(state().transactions.length,9,'transaction saved in tab');
const createdTx=state().transactions[0].id;
submit('form-transaction',{title:'Edited sample expense',type:'expense',category:'Food',amount:'20',accountId:'cash',date:new Date().toISOString().slice(0,10)},{id:createdTx});
assert.ok(state().transactions.some(tx=>tx.id===createdTx && tx.title==='Edited sample expense'),'transaction can be edited');
click('[data-action]',{action:'add-transaction'});
assert.match(element('modal-root').innerHTML,/form-transaction/,'add dialog opens');
click('#demo-navigation [data-screen]',{screen:'dashboard'});
assert.match(html(),/\$12,853\.00/,'expense updates derived account balance');
click('#demo-navigation [data-screen]',{screen:'budgets'});
assert.match(html(),/Food/,'budget page rendered');
submit('form-budget',{limit:'500'},{cat:'Food'});
assert.match(html(),/\$500\.00/,'budget limit changes');
click('#demo-navigation [data-screen]',{screen:'analytics'});
assert.match(html(),/Cash flow/,'analytics page rendered');
click('#demo-navigation [data-screen]',{screen:'plans'});
assert.match(html(),/Wireless headphones/,'plans page rendered');
submit('form-plan',{name:'Sample laptop stand',price:'45',category:'Shopping'});
const planId=state().plans[0].id;
assert.match(html(),/Sample laptop stand/,'new plan appears');
submit('form-buy-plan',{accountId:'bank'},{id:planId});
assert.equal(state().plans[0].purchased,true,'purchased plan marked');
assert.ok(state().transactions.some(t=>t.title==='Sample laptop stand'&&t.type==='expense'&&t.amount===45),'buy records expense');
click('#demo-navigation [data-screen]',{screen:'subscriptions'});
submit('form-subscription',{name:'Demo backup',price:'5',category:'Bills',accountId:'bank',frequency:'Monthly'});
assert.match(html(),/Demo backup/,'new subscription appears');
const countBeforeTransfer=state().transactions.length;
submit('form-transaction',{title:'Sample transfer',type:'transfer',amount:'75',accountId:'bank',toAccountId:'savings',date:new Date().toISOString().slice(0,10)});
assert.equal(state().transactions.length,countBeforeTransfer+1,'transfer is saved');
const transfer=state().transactions[0];
assert.equal(transfer.toAccountId,'savings','transfer destination saved');
click('#demo-navigation [data-screen]',{screen:'dashboard'});
assert.match(html(),/\$12,808\.00/,'transfer does not affect combined balances');
submit('form-delete-tx',{},{id:transfer.id});
assert.equal(state().transactions.length,countBeforeTransfer,'transaction delete works');
submit('form-reset-demo',{});
assert.equal(state().transactions.length,8,'reset restores seeded transactions');
assert.equal(state().budgets.Food,300,'reset restores budgets');
assert.match(html(),/\$12,873\.00/,'reset restores initial balance');
console.log('PASS: dashboard totals; navigation; transactions and HTML escaping; budgets; analytics; planned purchase; subscriptions; reset.');
