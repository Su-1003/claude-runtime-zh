"use strict";
const {execFileSync} = require("node:child_process");
const fs = require("node:fs");
const vm = require("node:vm");
const path = require("node:path");
const assert = require("node:assert/strict");
const ps = `
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Join-Path (Get-Location) 'launch-zh.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
foreach($name in @('Get-InjectionBody','New-ConsolePayload')){
 $definition=@($ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object {$_.Name -eq $name})
 if($definition.Count -ne 1){throw 'Missing unique payload function'}
 . ([scriptblock]::Create($definition[0].Extent.Text))
}
$scriptPath=Join-Path (Get-Location) 'claude-zh.js'
$nativeMenuPath=Join-Path (Get-Location) 'native-menu-zh.js'
$Configuration=$false; $Restore=$false
$apply=New-ConsolePayload (Get-InjectionBody) 'if (!window.__claudeRuntimeZh.status().active) throw new Error("not active");' '0123456789abcdef0123456789abcdef' $false
$Restore=$true
$restorePayload=New-ConsolePayload (Get-InjectionBody) 'if(window.__claudeRuntimeZh) throw new Error("still active");' '0123456789abcdef0123456789abcdef' $false
function Set-Clipboard { param([string]$Value) $script:capturedSnippet=$Value }
. (Join-Path (Get-Location) 'copy-script.ps1') 6>$null
$manualApply=$script:capturedSnippet
. (Join-Path (Get-Location) 'copy-script.ps1') -Restore 6>$null
$manualRestore=$script:capturedSnippet
@{apply=$apply;restore=$restorePayload;manualApply=$manualApply;manualRestore=$manualRestore} | ConvertTo-Json -Compress
`;
const generated = JSON.parse(execFileSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
  {cwd: __dirname, encoding: "utf8", maxBuffer: 24 * 1024 * 1024}));
const dom = fs.readFileSync(path.join(__dirname, "claude-zh.js"), "utf8");
assert(generated.apply.includes(dom));
const domStub = "window.__claudeRuntimeZh={status:()=>({active:true}),restore(){delete window.__claudeRuntimeZh;}};";
const apply = generated.apply.replace(dom, domStub);
function fixture(options = {}) {
  const logs = []; const store = new Map(); let locale = options.restore ? "zh-Hans" : "en-US";
  if (options.restore) store.set("__claudeNativeMenuZhBackupV1", JSON.stringify({version:1,previousLocale:"en-US",targetLocale:"zh-Hans"}));
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  const api = {getInitialLocale: async () => ({locale}), requestLocaleChange: async next => {
    await gate; if (options.reject) throw Error("blocked"); locale = next;
  }};
  const context = vm.createContext({location:{protocol:"app:",hostname:"localhost"},
    "claude.hybrid": options.missing ? {} : {DesktopIntl:api},
    localStorage: {getItem:k=>store.get(k)??null,setItem:(k,v)=>store.set(k,v),removeItem:k=>store.delete(k)},
    console:{info:v=>logs.push(String(v)),error:v=>logs.push(String(v)),warn:v=>logs.push(String(v))}});
  context.window=context;
  if(options.restore) context.__claudeRuntimeZh={restore(){delete context.__claudeRuntimeZh;}};
  return {context,logs,release,locale:()=>locale};
}
const tick = () => new Promise(resolve => setImmediate(resolve));
(async()=>{
  let count=0;
  const f=fixture(); const run=vm.runInContext("(async()=>{"+apply+"})()",f.context);
  await tick(); assert(!f.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  f.release(); await run; assert.equal(f.locale(),"zh-Hans"); assert(f.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  const bad=fixture({reject:true}); const failed=vm.runInContext("(async()=>{"+apply+"})()",bad.context);
  bad.release(); await failed; assert(bad.logs.some(x=>x.startsWith("CLAUDE_ZH_FAILED:"))); assert(!bad.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  const r=fixture({restore:true}); const restored=vm.runInContext("(async()=>{"+generated.restore+"})()",r.context);
  await tick(); assert(!r.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  r.release(); await restored; assert.equal(r.locale(),"en-US"); assert(r.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  const web=fixture({missing:true}); await vm.runInContext("(async()=>{"+apply+"})()",web.context);
  assert(web.logs.some(x=>x.includes("bridge unavailable"))); assert(web.logs.some(x=>x.startsWith("CLAUDE_ZH_OK_"))); count++;
  assert(generated.manualApply.includes(dom));
  const manual=fixture(); manual.release();
  for(let i=0;i<2;i++) await vm.runInContext("(async()=>{"+generated.manualApply.replace(dom,domStub)+"})()",manual.context);
  assert.equal(manual.locale(),"zh-Hans"); count++;
  await vm.runInContext("(async()=>{"+generated.manualRestore+"})()",manual.context);
  assert.equal(manual.locale(),"en-US"); assert.equal(manual.context.__claudeRuntimeZh,undefined); count++;
  console.log(JSON.stringify({passed:true,test_count:count,ui_actions_performed:false}));
})().catch(error=>{console.error(error);process.exitCode=1;});
