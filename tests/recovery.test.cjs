const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const vm = require('vm');
const { EventEmitter } = require('events');
const root = path.resolve(__dirname, '..');
const payload = fs.readFileSync(path.join(root, 'payload/ad-white-screen-recovery.js'), 'utf8');

function mock() {
  const shortcuts = new Map();
  const timers = new Map();
  const logLines = [];
  let now = 10000, timerId = 0;
  const app = new EventEmitter();
  app.getPath = () => '/game-profile';
  app.getAppMetrics = () => [{type:'Tab',memory:{workingSetSize:100,privateBytes:80}}];
  const contents = new EventEmitter();
  contents.isDestroyed = () => false;
  contents.soft = 0; contents.hard = 0; contents.reloads = 0;
  contents.reloadIgnoringCache = () => { contents.soft++; };
  contents.forcefullyCrashRenderer = () => { contents.hard++; };
  contents.reload = () => { contents.reloads++; };
  const win = new EventEmitter();
  win.focused = true;
  win.isFocused = () => win.focused;
  win.isDestroyed = () => false;
  win.webContents = contents;
  const api = {
    app, globalShortcut: {
      register: (key, callback) => { if (shortcuts.has(key)) return false; shortcuts.set(key, callback); return true; },
      unregister: key => shortcuts.delete(key)
    }
  };
  const localFs = {mkdirSync(){},existsSync(){return false;},statSync(){return{size:0};},appendFileSync(_file,text){logLines.push(JSON.parse(text));}};
  const context = { module:{exports:{}},require:name=>name==='electron'?api:name==='fs'?localFs:require(name),
    process:{versions:{electron:'mock'}},Date:class extends Date {static now(){return now;}},
    setTimeout:(callback,delay)=>{const id=++timerId;timers.set(id,{callback,delay});return id;},
    clearTimeout:id=>timers.delete(id),console
  };
  vm.runInNewContext(payload,context,{filename:'ad-white-screen-recovery.js'});
  context.module.exports.attach(win);
  return {win,contents,app,shortcuts,timers,logLines,attach:()=>context.module.exports.attach(win),advance:()=>{now+=3000;}};
}

let m=mock();
assert.equal(m.shortcuts.size,2,'register both focused shortcuts');
m.attach(); assert.equal(m.win.listenerCount('focus'),1,'attach is idempotent');
m.shortcuts.get('F5')();
assert.equal(m.contents.soft,1); assert.equal(m.timers.size,1);
m.shortcuts.get('F5')(); assert.equal(m.contents.soft,1,'debounce repeat');
m.contents.emit('did-finish-load'); assert.equal(m.timers.size,0,'loaded page cancels fallback');
m.win.focused=false; m.win.emit('blur'); assert.equal(m.shortcuts.size,0,'other apps retain shortcuts');
m.win.focused=true; m.win.emit('focus'); assert.equal(m.shortcuts.size,2);
m.advance(); m.shortcuts.get('F5')();
const timer=[...m.timers.values()][0]; assert.equal(timer.delay,8000);
timer.callback(); assert.equal(m.contents.hard,1); assert.equal(m.contents.reloads,1);
assert.equal(m.timers.size,0,'fallback is one-shot');
m.advance(); m.win.emit('unresponsive'); m.shortcuts.get('CommandOrControl+Alt+R')();
assert.equal(m.contents.hard,2); assert.equal(m.contents.reloads,2,'unresponsive window recreates renderer directly');
m.contents.emit('render-process-gone',{}, {reason:'oom',exitCode:9});
assert(m.logLines.some(line=>line.event==='renderer-gone'&&line.reason==='oom'),'record crash reason');
m.win.emit('closed'); assert.equal(m.shortcuts.size,0); assert.equal(m.timers.size,0);
m=mock(); m.shortcuts.get('F5')(); m.app.emit('before-quit'); assert.equal(m.shortcuts.size,0); assert.equal(m.timers.size,0);
m=mock(); m.contents.reloadIgnoringCache=()=>{throw Error('test failure');}; m.shortcuts.get('F5')();
assert.equal(m.contents.hard,1); assert.equal(m.timers.size,0,'reload error falls back safely');
console.log('PASS: focused shortcut lifecycle, debounce, successful reload, timeout fallback, unresponsive recovery, crash logging, shutdown cleanup, reload-error fallback.');

if(process.argv.length>3){
  function archive(file){const buf=fs.readFileSync(file);const size=buf.readUInt32LE(4);const len=buf.readUInt32LE(12);const tree=JSON.parse(buf.subarray(16,16+len));const entries=new Map();function walk(files,prefix=''){for(const [name,item]of Object.entries(files)){const full=prefix?prefix+'/'+name:name;if(item.files)walk(item.files,full);else entries.set(full,item);}}walk(tree.files);return{buf,base:8+size,entries};}
  const original=archive(process.argv[2]),patched=archive(process.argv[3]);
  function bytes(a,e){assert(!e.unpacked,'fixture unexpectedly includes unpacked entry');return a.buf.subarray(a.base+Number(e.offset),a.base+Number(e.offset)+e.size);}
  let unchanged=0,unpacked=0;
  for(const [name,entry]of original.entries){if(name==='main.js')continue;const other=patched.entries.get(name);assert(other,'missing '+name);if(entry.link){assert.equal(other.link,entry.link);continue;}if(entry.unpacked){assert.deepEqual(other,entry,'changed unpacked metadata '+name);unpacked++;continue;}assert(bytes(original,entry).equals(bytes(patched,other)),'changed '+name);unchanged++;}
  const oldMain=bytes(original,original.entries.get('main.js')).toString();const newMain=bytes(patched,patched.entries.get('main.js')).toString();
  const injected="  // AD-WHITE-SCREEN-RECOVERY:1.0.0\r\n  require('./ad-white-screen-recovery').attach(mainWindow)\r\n\r\n";
  assert.equal(newMain.replace(injected,''),oldMain,'main differs beyond intended hook');
  assert.equal(bytes(patched,patched.entries.get('ad-white-screen-recovery.js')).toString(),payload);
  new vm.Script(newMain); new vm.Script(payload);
  assert.equal(patched.entries.size,original.entries.size+1);
  console.log(`PASS: ${unchanged} packed entries preserved byte-for-byte, ${unpacked} external-file descriptors unchanged; main.js only adds the recovery hook; exactly one module added; both JavaScript files parse.`);
}
