"use strict";

const riskNames = {
  high: "高风险 · 静态规则",
  medium: "中风险 · 需要核对",
  insufficient_evidence: "证据不足 · 不能确认",
};

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function addDetail(parent, label, value) {
  const item = element("div", "detail-row");
  item.append(element("dt", "detail-key", label), element("dd", "detail-content", value ?? "未提供"));
  parent.append(item);
}

function showCards(cases) {
  const grid = document.querySelector("#case-grid");
  grid.replaceChildren();
  cases.forEach((item, index) => {
    const card = element("article", `route-card tone-${item.tone}`);
    const top = element("div", "route-top");
    top.append(element("span", "route-number", String(index + 1).padStart(2, "0")), element("span", "route-source", item.section));
    card.append(top, element("h3", "route-title", item.title), element("p", "route-summary", item.summary));
    const bottom = element("div", "route-bottom");
    bottom.append(element("span", "route-kind", item.expected_parse.input_type === "intent" ? "Intent URI" : item.expected_parse.input_type === "url" ? "网页链接" : "自定义 Scheme"));
    const link = element("a", "route-action", item.button + " ↗");
    link.href = `deep-link-preview.html?case=${encodeURIComponent(item.id)}`;
    bottom.append(link);
    card.append(bottom);
    grid.append(card);
  });
}

function showPreview(item) {
  const main = document.querySelector("#preview-main");
  main.replaceChildren();

  const intro = element("section", "preview-intro");
  intro.append(element("p", "kicker", `STATIC ROUTE CHECK / ${item.id}`), element("h1", "", "打开 App 之前，先看清链接会去哪里。"), element("p", "preview-lead", `你刚从「${item.section}」点击了「${item.button}」。这一步只展示测试样例的静态预期，不会启动任何应用。`));
  main.append(intro);

  const layout = element("div", "preview-layout");
  const phone = element("section", "phone-frame");
  const phoneScreen = element("div", "phone-screen");
  const phoneStatus = element("div", "phone-status");
  phoneStatus.append(element("span", "", "9:41"), element("span", "", "●●●  ▰"));
  phoneScreen.append(phoneStatus, element("div", "phone-app-label", "槐序 Campus  ·  演示场景"));
  const message = element("div", "phone-message");
  message.append(element("span", "phone-message-icon", "槐"), element("p", "", `你正在查看：${item.title}`), element("small", "", item.summary));
  phoneScreen.append(message);
  const sheet = element("div", "phone-sheet");
  sheet.append(element("span", "sheet-grip"), element("div", "sheet-icon", "↗"), element("h2", "", "即将离开当前页面"), element("p", "", "一个链接请求打开其他目标。实际手机系统的确认弹窗可能因设备而异。"));
  const routePreview = item.input.startsWith("intent://") ? "intent://…" : item.expected_parse.scheme ? `${item.expected_parse.scheme}://…` : "无法解析目标";
  sheet.append(element("div", "sheet-target", routePreview));
  sheet.append(element("div", "sheet-button", "仅演示 · 未打开"));
  phoneScreen.append(sheet);
  phone.append(phoneScreen);
  layout.append(phone);

  const report = element("section", "inspection-card");
  const risk = element("span", `risk-badge risk-${item.risk_label}`, riskNames[item.risk_label]);
  report.append(element("p", "eyebrow", "TAPLENS / 预期本地结果"), risk, element("h2", "", item.title), element("p", "inspection-summary", item.interpretation));

  const fields = element("dl", "inspection-details");
  const parsed = item.expected_parse;
  addDetail(fields, "解析状态", parsed.status === "succeeded" ? "成功" : "失败 · 证据不足");
  addDetail(fields, "Scheme", parsed.scheme);
  addDetail(fields, "目标域 / Host", parsed.host);
  addDetail(fields, "路径", parsed.path);
  addDetail(fields, "指定包名", parsed.package_name);
  addDetail(fields, "预期包名", item.expected_package_name);
  addDetail(fields, "浏览器回退", parsed.fallback_url);
  addDetail(fields, "参数 / Extras 名称", [...parsed.parameter_names, ...parsed.extra_names].join(", ") || null);
  addDetail(fields, "预期本地证据", item.expected_local_ids.join(", ") || "无");
  report.append(fields);

  const evidence = element("div", "evidence-note");
  evidence.append(element("strong", "", "规则提示"), element("span", "", item.expected_local_risk_hints.join("  ·  ")));
  report.append(evidence);

  const payload = element("div", "payload-box");
  payload.append(element("span", "payload-label", "用于 C 模块解析的固定输入"), element("code", "", item.input));
  report.append(payload);
  const actions = element("div", "preview-actions");
  const copy = element("button", "button button-dark", "复制测试链接");
  copy.type = "button";
  copy.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(item.input);
      copy.textContent = "已复制，可粘贴到 TapLens";
    } catch {
      copy.textContent = "复制不可用，请手动选取上方链接";
    }
  });
  actions.append(copy);
  const back = element("a", "button button-outline", "换一个入口");
  back.href = "deep-link-demo.html#all-cases";
  actions.append(back);
  report.append(actions);
  if (item.id === "FIX-DL-007") {
    const note = element("p", "cloud-note");
    note.append("这个网址是逻辑样例，不可直接访问。B 可在隔离测试环境中将它精确映射到 ");
    const local = element("a", "", "本站受控跳转页");
    local.href = "short-link.html";
    note.append(local, "，采集真实跳转与表单证据；这里不生成 Cxx。");
    report.append(note);
  }
  layout.append(report);
  main.append(layout);
}

async function init() {
  try {
    const response = await fetch("deep-link-demo-data.json", { cache: "no-store" });
    if (!response.ok) throw new Error("local fixture unavailable");
    const cases = await response.json();
    if (document.body.dataset.page === "entry") {
      showCards(cases);
      return;
    }
    const id = new URLSearchParams(window.location.search).get("case");
    const item = cases.find((entry) => entry.id === id);
    if (!item) throw new Error("unknown fixture ID");
    showPreview(item);
  } catch {
    const root = document.body.dataset.page === "entry" ? document.querySelector("#case-grid") : document.querySelector("#preview-main");
    root.replaceChildren(element("p", "load-error", "本地样例未载入。请通过 HTTP 静态服务打开此页面，并检查样例编号。"));
  }
}

init();
