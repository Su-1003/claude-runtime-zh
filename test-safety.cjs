"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const script = fs.readFileSync(path.join(__dirname, "claude-zh.js"), "utf8");
for (const location of [
  {protocol: "https:", hostname: "example.com"},
  {protocol: "https:", hostname: "claude.ai.example.com"},
  {protocol: "http:", hostname: "claude.ai"},
  {protocol: "file:", hostname: "", pathname: "/Users/example/document.html"}
]) {
  assert.throws(() => vm.runInNewContext(script, {location,
    document: {documentElement: {hasAttribute: () => false}}}), /请选择 Claude/);
}
const dictionary = JSON.parse(fs.readFileSync(path.join(__dirname, "dictionary.json"), "utf8"));
for (const key of Object.keys(dictionary)) {
  assert(!["hours", "hour", "minutes", "minute", "seconds", "second"].includes(key.toLowerCase()));
  assert(!/[{}]/.test(key));
}
console.log("PASS: blocked origins, unit identifiers, and template exclusions.");
