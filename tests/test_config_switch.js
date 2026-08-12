"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const configModel = fs.readFileSync(path.join(
  __dirname,
  "../luci-app-openclash/luasrc/model/cbi/openclash/config.lua"
), "utf8");

const switchHandler = configModel.match(
  /btnis\.write=function\(a,t\)([\s\S]*?)\nend/
);

assert(switchHandler, "配置管理页面缺少切换处理函数");

const body = switchHandler[1];
const setPathAt = body.indexOf('uci:set("openclash", "config", "config_path"');
const enableAt = body.indexOf('uci:set("openclash", "config", "enable", "1")');
const commitAt = body.indexOf('uci:commit("openclash")');
const restartAt = body.indexOf('SYS.call("/etc/init.d/openclash restart');

assert(setPathAt >= 0, "切换配置时未写入 config_path");
assert(enableAt > setPathAt, "切换配置时未启用 OpenClash");
assert(commitAt > enableAt, "切换配置时未提交启用状态");
assert(restartAt > commitAt, "切换配置后未重启 OpenClash");

console.log("config_switch_tests: ok");
