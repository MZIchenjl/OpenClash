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
const packageMakefile = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/Makefile"
), "utf8");
const settings = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/luasrc/model/cbi/openclash/settings.lua"
), "utf8");
const watchdog = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/root/usr/share/openclash/openclash_watchdog.sh"
), "utf8");
const initScript = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/root/etc/init.d/openclash"
), "utf8");
const updater = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/root/usr/share/openclash/openclash_efan_update.sh"
), "utf8");
const chinesePo = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/po/zh-cn/openclash.zh-cn.po"
), "utf8");

assert(settings.includes('Flag, "efan_auto_update"'), "Efan auto-update switch is missing");
assert(packageMakefile.includes('+ruby-gems +ruby-base64'), "Efan runtime must load packaged Ruby gems");
assert(settings.includes('ListValue, "efan_update_week_time"'), "Efan weekly schedule is missing");
assert(settings.includes('ListValue, "efan_update_day_time"'), "Efan daily hour is missing");
assert(settings.includes('DummyValue, "_efan_last_update"'), "Efan last-update display is missing");
assert(!settings.includes('"efan_update_interval"'), "legacy minute interval is still visible");
assert(initScript.includes('openclash_efan_update.sh #openclash-cron-task'), "OpenClash cron does not schedule Efan updates");
assert(initScript.includes('efan_update_week_time'), "Efan cron has no weekday field");
assert(initScript.includes('efan_update_day_time'), "Efan cron has no hour field");
assert(!watchdog.includes('EFAN_UPDATE_INT'), "watchdog still contains the legacy minute scheduler");
assert(updater.includes('refresh-all'), "Efan updater does not refresh remembered accounts");
assert(updater.includes('efan_last_update_time'), "Efan updater does not save its last successful update");
assert(updater.includes('efan_last_update_status'), "Efan updater does not save its last status");
assert(chinesePo.includes('msgid "Efan Account"\nmsgstr "Efan 账号"'), "Efan tab has no Chinese translation");
assert(chinesePo.includes('msgid "Refresh all services"\nmsgstr "更新全部服务"'), "Efan refresh button has no Chinese translation");
assert(chinesePo.includes('msgid "Last Automatic Update"\nmsgstr "上次自动更新"'), "Efan last-update label has no Chinese translation");
assert(template.includes('id="efan-login-button" onclick="EfanAccount.login()"><%:Login%>'), "Efan login button is not concise");
assert(!template.includes('<%:Login and fetch all services%>'), "legacy login button text is still used");
assert(template.includes('class="efan-table-wrap"'), "Efan services are not wrapped as a responsive table");
assert(template.includes('border-collapse: collapse'), "Efan services table has no visible grid styling");
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
  "efan-services-wrap",
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
assert.strictEqual(elements["efan-services-wrap"].style.display, "");
assert.strictEqual(elements["efan-services"].tbody.children.length, 2);
assert.strictEqual(account.accountStatus("Active"), "translated");
assert.strictEqual(account.errorLabel("login_failed"), "translated");
assert.strictEqual(account.errorLabel("http_503"), "translated");

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
