"use strict";
(() => {
  const $ = id => document.getElementById(id);
  const wait = () => new Promise(resolve => setTimeout(resolve, 230));
  let clicks = 0, running = false;
  $("save").addEventListener("click", () => clicks++);
  function install() {
    return new Promise((resolve, reject) => {
      const tag = document.createElement("script");
      tag.src = "claude-zh.js";
      tag.onload = () => { tag.remove(); resolve(); };
      tag.onerror = () => { tag.remove(); reject(new Error("Cannot load claude-zh.js")); };
      document.body.appendChild(tag);
    });
  }
  async function run() {
    if (running) return;
    running = true;
    const results = [];
    const check = (name, value) => {
      results.push({name, passed: !!value});
      if (!value) throw new Error(name);
    };
    const added = document.createElement("button");
    try {
      document.documentElement.dataset.testStatus = "running";
      await install();
      check("按钮与标题翻译", $("new-chat").textContent === "新建聊天" && $("heading").textContent === "设置");
      check("输入框值与用户输入保留", $("name").value === "hours" && $("composer").value === "Save hours");
      check("占位与辅助标签翻译", $("name").placeholder === "搜索" && $("save").getAttribute("aria-label") === "保存");
      check("代码和时间单位保持原样", $("code").textContent === 'const unit = "hours"; const options = { hours: 2 };');
      check("标签中的 hours 与模板不替换", $("unit").textContent === "hours" && $("template").textContent === "{hours}");
      check("会话中的标题和按钮保持原样", $("protected-heading").textContent === "Settings" && $("message-button").textContent === "Save");
      check("设置页普通 div 标签翻译", $("setting-label").textContent === "界面字体");
      check("设置页普通段落与长文说明翻译", $("setting-description").textContent.includes("整个界面") && $("memory-description").textContent.includes("本机"));
      check("弯引号隐私标题和列表翻译", $("privacy-heading").textContent.includes("不会看到") && $("privacy-item").textContent.includes("对话内容"));
      check("隐私声明保留动态地址", $("privacy-whole").textContent.includes("推理服务商（127.0.0.1:15721）"));
      check("分节点隐私声明与嵌入元素保留", $("privacy-split").textContent.startsWith("你正在") && $("provider-host").textContent === "127.0.0.1:15721");
      check("设置页内的会话内容仍然保护", $("settings-user-content").textContent === "Interface font");
      check("不扩大到其他对话框正文", $("other-dialog").textContent === "Interface font");
      const previous = clicks; $("save").click();
      check("原有点击事件仍有效", clicks === previous + 1);
      added.textContent = "Cancel";
      $("fixture").appendChild(added);
      await wait();
      check("动态新增元素翻译", added.textContent === "取消");
      $("dynamic").firstChild.data = "Back";
      await wait();
      check("页面重绘后的标签翻译", $("dynamic").textContent === "返回");
      const oldController = window.__claudeRuntimeZh;
      await install();
      check("重复启用替换旧实例", oldController.status().active === false && window.__claudeRuntimeZh.status().active);
      $("save").removeAttribute("title");
      window.__claudeRuntimeZh.restore();
      check("恢复原始标签与占位", $("save").textContent === "Save" && $("name").placeholder === "Search");
      check("恢复不覆盖应用已经移除的属性", !$("save").hasAttribute("title"));
      check("恢复使用最新英文标签", $("dynamic").textContent === "Back");
      check("设置说明和隐私声明可恢复", $("setting-label").textContent === "Interface font" && $("privacy-whole").textContent.startsWith("You’re running"));
      check("恢复后解除全局控制器", !window.__claudeRuntimeZh);
      added.firstChild.data = "Download";
      await wait();
      check("恢复后停止观察", added.textContent === "Download");
      $("save").setAttribute("title", "Save changes");
      await install();
      check("恢复后可以再次启用", $("save").getAttribute("title") === "保存更改");
    } catch (error) {
      results.push({name: "异常：" + error.message, passed: false});
    } finally {
      added.remove();
      const passed = results.length > 0 && results.every(x => x.passed);
      window.__claudeZhTestResults = results;
      document.documentElement.dataset.testStatus = passed ? "passed" : "failed";
      $("test-results").className = passed ? "test-good" : "test-bad";
      $("test-results").textContent = JSON.stringify({passed, tests: results}, null, 2);
      running = false;
    }
  }
  $("enable").addEventListener("click", () => install());
  $("restore").addEventListener("click", () => window.__claudeRuntimeZh?.restore());
  $("rerun").addEventListener("click", run);
  run();
})();
