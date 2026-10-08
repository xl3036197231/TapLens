"use strict";

const MANIFEST_URL = "../../../../shared/datasets/qr/manifest.json";
const PNG_BASE = "../../../../shared/datasets/qr/";
const tones = {
  campus: { wash: "#c8d9c5", paper: "#fdf9e9", ink: "#2c513e", angle: "-4deg" },
  community: { wash: "#d8d2e8", paper: "#fff", ink: "#533f82", angle: "2deg" },
  wifi: { wash: "#c4dad8", paper: "#e8f5ef", ink: "#1d5553", angle: "-3deg" },
  sms: { wash: "#ecdbbf", paper: "#fffbec", ink: "#805326", angle: "3deg" },
  phone: { wash: "#dad8cb", paper: "#fefcf4", ink: "#4e5949", angle: "-2deg" },
  email: { wash: "#d9ddec", paper: "#fafaff", ink: "#4e567f", angle: "3deg" },
  contact: { wash: "#d9e6d2", paper: "#fafcf4", ink: "#426c49", angle: "-4deg" },
  download: { wash: "#aebac0", paper: "#202f36", ink: "#e7ffe7", angle: "2deg" },
  store: { wash: "#f0d9ca", paper: "#fff9f5", ink: "#9c4b32", angle: "-2deg" },
  text: { wash: "#eddfbd", paper: "#fef9e8", ink: "#796134", angle: "4deg" },
  broken: { wash: "#dcdfdb", paper: "#f7f7f2", ink: "#68716c", angle: "-5deg" }
};
const groups = {
  link: new Set(["QR01", "QR02", "QR08", "QR09", "QR12", "QR13"]),
  system: new Set(["QR03", "QR04", "QR05", "QR06", "QR07"]),
  content: new Set(["QR10", "QR11"])
};
const typeLabels = {
  http_url: "网址 / 可能跳转", intent_deep_link: "Intent / 应用深链",
  wifi: "Wi‑Fi 配置", sms: "短信草稿", phone: "电话号码",
  email: "电子邮件草稿", vcard: "电子名片", apk_download: "APK 下载地址",
  app_store: "应用商店地址", plain_text: "普通文本", invalid_content: "无法识别的内容"
};

function el(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined) node.textContent = value;
  return node;
}

function productUrl(item) {
  if (!item.related_deep_link_fixture_id) return null;
  const url = new URL(item.source_product_url);
  if (url.protocol !== "https:" || url.hostname !== "item.taobao.com" || url.pathname !== "/item.htm" ||
      url.username || url.password || url.hash || [...url.searchParams.keys()].join() !== "id" ||
      !/^\d+$/.test(url.searchParams.get("id") || "") || url.href !== item.payload) {
    throw new Error("商品二维码必须编码固定淘宝商品 HTTPS 地址");
  }
  return url.href;
}

function showPreview(item) {
  const fields = {
    "preview-id": item.id + " / 预期结果", "preview-title": item.scene.headline,
    "preview-origin": item.scene.surface, "preview-type": typeLabels[item.expected_type] || item.expected_type,
    "preview-value": item.expected_preview, "preview-action": item.possible_action,
    "preview-risk": item.risk_explanation, "preview-safe": item.taplens_action
  };
  for (const [id, value] of Object.entries(fields)) document.getElementById(id).textContent = value;
  const pair = document.getElementById("preview-pair");
  pair.replaceChildren();
  pair.hidden = !item.related_deep_link_fixture_id;
  if (item.related_deep_link_fixture_id) {
    pair.append(document.createTextNode(`场景声称打开 ${item.claimed_app}；二维码实际指向 ${item.target_app}商品网页。配对 Deep Link 另行声明淘宝应用包名。`));
    const link = el("a", "", `查看配对 Deep Link ${item.related_deep_link_fixture_id}`);
    link.href = `deep-link-preview.html?case=${encodeURIComponent(item.related_deep_link_fixture_id)}`;
    pair.append(link);
  }
  const product = document.getElementById("preview-product");
  product.replaceChildren();
  product.hidden = !item.related_deep_link_fixture_id;
  if (item.related_deep_link_fixture_id) {
    const link = el("a", "", "打开实际编码的淘宝商品页 ↗");
    link.href = productUrl(item);
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    product.append(link);
  }
  document.getElementById("preview-dialog").showModal();
}

function showQr(item) {
  document.getElementById("scan-id").textContent = item.id + " / 供手机实扫";
  document.getElementById("scan-title").textContent = item.scene.headline;
  const image = document.getElementById("scan-image");
  image.src = PNG_BASE + item.png;
  image.alt = item.id + " 放大的测试二维码";
  document.getElementById("scan-guidance").textContent = item.related_deep_link_fixture_id
    ? "使用手机扫码可打开二维码中的链接；使用 TapLens 会先看到安全预览，再决定是否访问。放大图片本身不会打开外站。"
    : "请使用另一台设备上的 TapLens 安全预览进行实扫，或从相册导入原始 PNG。不要用系统扫码器直接打开链接或执行动作。这里展示的是固定样例，不会自动产生 Lxx/Cxx 证据。";
  document.getElementById("scan-dialog").showModal();
}

function card(item, index) {
  if (!/^QR\d{2}$/.test(item.id) || !/^png\/qr[\w-]+\.png$/.test(item.png) || !tones[item.scene.tone]) {
    throw new Error("二维码清单包含无效的展示字段");
  }
  const node = el("article", "scene-card");
  node.id = item.id;
  node.dataset.id = item.id;
  node.dataset.tone = item.scene.tone;
  const tone = tones[item.scene.tone];
  for (const [name, value] of Object.entries(tone)) node.style.setProperty("--" + name, value);
  const art = el("div", "scene-art");
  art.append(el("span", "surface-label", item.scene.surface));
  const artifact = el("div", "artifact");
  const copy = el("div", "artifact-copy");
  copy.append(el("span", "SCENE / " + String(index + 1).padStart(2, "0")), el("strong", "", item.scene.headline), el("small", "", item.scene.scan_prompt));
  const zoom = el("button", "qr-enlarge");
  zoom.type = "button";
  zoom.setAttribute("aria-label", "放大 " + item.id + " 二维码供手机扫码");
  zoom.title = "放大二维码供手机扫码";
  zoom.addEventListener("click", () => showQr(item));
  const image = el("img", "qr-image");
  image.src = PNG_BASE + item.png;
  image.alt = item.id + " 测试二维码；内容见扫码预览与 manifest";
  image.width = 102;
  image.height = 102;
  zoom.append(image);
  artifact.append(copy, zoom);
  art.append(artifact);
  const body = el("div", "scene-body");
  const meta = el("div", "scene-meta");
  meta.append(el("span", "", item.id), el("span", "", item.related_deep_link_fixture_id ? "哔哩哔哩视频" : typeLabels[item.expected_type] || item.expected_type));
  const button = el("button", "preview-button");
  button.type = "button";
  button.append(document.createTextNode(item.related_deep_link_fixture_id ? "TapLens 扫码 · 安全预览" : "模拟扫码 · 查看预期预览"), el("span", "", "↗"));
  button.addEventListener("click", () => showPreview(item));
  body.append(meta, el("h3", "", item.scene.headline), el("p", "", item.scene.body), button);
  if (item.related_deep_link_fixture_id) {
    const product = el("a", "external-product-link", "在哔哩哔哩观看 ↗");
    product.href = productUrl(item);
    product.target = "_blank";
    product.rel = "noopener noreferrer";
    body.append(product);
  }
  node.append(art, body);
  return node;
}

async function init() {
  const grid = document.getElementById("scene-grid");
  try {
    const response = await fetch(MANIFEST_URL, { cache: "no-store" });
    if (!response.ok) throw new Error("HTTP " + response.status);
    const manifest = await response.json();
    if (!Array.isArray(manifest.cases) || manifest.cases.length !== 11 || !Array.isArray(manifest.supplemental_cases) || manifest.supplemental_cases.length !== 2) throw new Error("样例数量不匹配");
    const cases = [...manifest.cases, ...manifest.supplemental_cases];
    grid.replaceChildren(...cases.map(card));
    if (/^#QR\d{2}$/.test(window.location.hash)) {
      document.getElementById(window.location.hash.slice(1))?.scrollIntoView({ block: "center" });
    }
  } catch (error) {
    grid.replaceChildren(el("p", "loading", "无法读取二维码样例。请在仓库根目录启动本地 HTTP 服务（端口 8767），再刷新页面。"));
    console.error("QR demo fixture load failed:", error);
  }
  document.getElementById("filters").addEventListener("click", (event) => {
    const target = event.target.closest("button[data-filter]");
    if (!target) return;
    const selected = target.dataset.filter;
    for (const button of document.querySelectorAll("#filters button")) button.setAttribute("aria-pressed", String(button === target));
    for (const scene of grid.querySelectorAll(".scene-card")) scene.hidden = selected !== "all" && !groups[selected]?.has(scene.dataset.id);
  });
  const dialog = document.getElementById("preview-dialog");
  for (const id of ["close-preview", "done-preview"]) document.getElementById(id).addEventListener("click", () => dialog.close());
  const scanDialog = document.getElementById("scan-dialog");
  for (const id of ["close-scan", "done-scan"]) document.getElementById(id).addEventListener("click", () => scanDialog.close());
}

init();
