"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const templatePath = path.join(
  __dirname,
  "../luci-app-openclash/luasrc/view/openclash/efan_login.htm"
);
const template = fs.readFileSync(templatePath, "utf8");
const settings = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/luasrc/model/cbi/openclash/settings.lua"
), "utf8");
const watchdog = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/root/usr/share/openclash/openclash_watchdog.sh"
), "utf8");
const updater = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/root/usr/share/openclash/openclash_efan_update.sh"
), "utf8");

assert(settings.includes('Flag, "efan_auto_update"'), "Efan auto-update switch is missing");
assert(settings.includes('Value, "efan_update_interval"'), "Efan update interval is missing");
assert(settings.includes('o:depends("efan_auto_update", "1")'), "Efan interval must depend on its switch");
assert(watchdog.includes('openclash_efan_update.sh'), "watchdog does not schedule Efan updates");
assert(updater.includes('refresh-all'), "Efan updater does not refresh remembered accounts");
const match = template.match(/<script[^>]*>([\s\S]*?)<\/script>/);
assert(match, "Efan template script is missing");

const script = match[1]
  .replace(/<%=([\s\S]*?)%>/g, "/test-endpoint")
  .replace(/<%:([\s\S]*?)%>/g, "translated");

class FakeElement {
  constructor(id) {
    this.id = id;
    this.style = {display: ""};
    this.disabled = false;
    this.readOnly = false;
    this.value = "";
    this.textContent = "";
    this.className = "";
    this.children = [];
    this.tbody = null;
  }

  appendChild(child) {
    this.children.push(child);
  }

  removeChild(child) {
    const index = this.children.indexOf(child);
    if (index >= 0) this.children.splice(index, 1);
  }

  get firstChild() {
    return this.children.length ? this.children[0] : null;
  }

  querySelector(selector) {
    return selector === "tbody" ? this.tbody : null;
  }
}

const elementIds = [
  "efan-account-state",
  "efan-account-summary",
  "efan-email",
  "efan-password-row",
  "efan-password",
  "efan-login-button",
  "efan-refresh-button",
  "efan-logout-button",
  "efan-message",
  "efan-services"
];
const elements = Object.fromEntries(elementIds.map((id) => [id, new FakeElement(id)]));
elements["efan-services"].tbody = new FakeElement("efan-services-body");

const localValues = {};
const context = {
  console,
  Array,
  Object,
  String,
  RegExp,
  encodeURIComponent,
  document: {
    getElementById: (id) => elements[id],
    createElement: (tag) => new FakeElement(tag),
    addEventListener: () => {}
  },
  window: {
    localStorage: {
      getItem: (key) => localValues[key] || null,
      setItem: (key, value) => { localValues[key] = value; },
      removeItem: (key) => { delete localValues[key]; }
    }
  }
};
context.localStorage = context.window.localStorage;
vm.runInNewContext(script, context, {filename: templatePath});

const account = context.EfanAccount;
assert(account, "EfanAccount was not initialized");

account.setState("logged_out");
assert.strictEqual(elements["efan-login-button"].style.display, "");
assert.strictEqual(elements["efan-login-button"].disabled, false);
assert.strictEqual(elements["efan-refresh-button"].style.display, "none");
assert.strictEqual(elements["efan-logout-button"].style.display, "none");
assert.strictEqual(elements["efan-password-row"].style.display, "");
assert.strictEqual(elements["efan-email"].readOnly, false);

const loggedIn = {
  status: "ok",
  session_state: "logged_in",
  service_count: 1,
  ready_count: 1,
  failed_count: 0,
  all_config_exists: true,
  all_config: "/etc/openclash/config/efan-test-all.yaml",
  services: [{
    id: 7,
    name: "Test service",
    account_status: "Active",
    status: "updated",
    nodes: 3,
    config: "/etc/openclash/config/efan-test-7.yaml"
  }]
};
account.setState("logged_in", loggedIn);
assert.strictEqual(elements["efan-login-button"].style.display, "none");
assert.strictEqual(elements["efan-refresh-button"].style.display, "");
assert.strictEqual(elements["efan-refresh-button"].disabled, false);
assert.strictEqual(elements["efan-logout-button"].style.display, "");
assert.strictEqual(elements["efan-logout-button"].disabled, false);
assert.strictEqual(elements["efan-password-row"].style.display, "none");
assert.strictEqual(elements["efan-email"].readOnly, true);

account.setState("refreshing", loggedIn);
assert.strictEqual(elements["efan-refresh-button"].style.display, "");
assert.strictEqual(elements["efan-refresh-button"].disabled, true);
assert.strictEqual(elements["efan-logout-button"].disabled, true);

account.render(loggedIn);
assert.strictEqual(elements["efan-services"].style.display, "");
assert.strictEqual(elements["efan-services"].tbody.children.length, 2);

account.authenticatedResult({
  status: "error",
  session_state: "expired",
  error: "service_auth_invalid",
  service_count: 1,
  services: []
}, "refresh");
assert.strictEqual(account.state, "expired");
assert.strictEqual(elements["efan-login-button"].style.display, "");
assert.strictEqual(elements["efan-refresh-button"].style.display, "none");

elements["efan-email"].value = "";
account.post = (_url, data, callback) => {
  assert.strictEqual(data.email, "");
  callback(Object.assign({email: "remembered@example.test"}, loggedIn), 200);
};
account.status(true);
assert.strictEqual(account.state, "logged_in");
assert.strictEqual(elements["efan-email"].value, "remembered@example.test");
assert.strictEqual(localValues[account.storageKey], "remembered@example.test");
assert.strictEqual(elements["efan-refresh-button"].disabled, false);

console.log("efan_luci_ui_tests: ok");
