const pages = [...document.querySelectorAll(".page")];
const navButtons = [...document.querySelectorAll("[data-target]")];
const currentTitle = document.querySelector("[data-current-title]");
const pageHeading = document.querySelector("[data-page-heading]");
const toastBox = document.querySelector("[data-toast-box]");
const modal = document.querySelector("[data-modal]");
const modalText = document.querySelector("[data-modal-text]");
const modalClose = document.querySelector("[data-modal-close]");
const modalOk = document.querySelector("[data-modal-ok]");
const menu = document.querySelector("[data-menu]");
const menuToggle = document.querySelector("[data-menu-toggle]");
const themeToggle = document.querySelector("[data-theme-toggle]");

const chartSets = {
  "1d": {
    labels: ["00:00", "04:00", "08:00", "12:00", "16:00", "20:00", "现在"],
    values: [0.4, 0.7, 1.2, 2.4, 3.1, 4.8, 6.2],
  },
  "3d": {
    labels: ["7/19 00", "7/19 12", "7/20 00", "7/20 12", "7/21 00", "7/21 12", "现在"],
    values: [7, 14, 28, 36, 48, 61, 73],
  },
  "7d": {
    labels: ["7/15", "7/16", "7/17", "7/18", "7/19", "7/20", "7/21"],
    values: [18, 25, 41, 56, 82, 119, 173.6],
  },
  "30d": {
    labels: ["7/01", "7/05", "7/10", "7/15", "7/20", "现在"],
    values: [6, 28, 54, 91, 142, 173.6],
  },
};

const codeSamples = {
  cloudflare: `Type: A
Name: cdt
Content: 203.0.113.10
Proxy status: Proxied
TTL: Auto`,
  caddy: `cdt.example.com {
  reverse_proxy 127.0.0.1:8787
}`,
  nginx: `server {
  listen 443 ssl http2;
  server_name cdt.example.com;

  location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}`,
};

let activeRange = "1d";

function cssVar(name) {
  return getComputedStyle(document.body).getPropertyValue(name).trim();
}

function applyTheme(theme) {
  document.body.dataset.theme = theme;
  localStorage.setItem("cdt-control-plane-theme", theme);
  if (themeToggle) {
    themeToggle.textContent = theme === "light" ? "深色模式" : "浅色模式";
  }
  requestAnimationFrame(() => drawChart(activeRange));
}

function openPage(id) {
  const page = document.getElementById(id);
  if (!page) return;

  pages.forEach((item) => item.classList.toggle("active", item.id === id));
  navButtons.forEach((button) => {
    if (button.classList.contains("nav-item")) {
      button.classList.toggle("active", button.dataset.target === id);
    }
  });

  const title = page.dataset.title || "总览";
  currentTitle.textContent = title;
  pageHeading.textContent = title;
  document.querySelector(".app-shell").dataset.view = id;
  menu?.classList.remove("open");
  window.scrollTo({ top: 0, behavior: "smooth" });

  if (id === "overview") {
    requestAnimationFrame(() => drawChart(activeRange));
  }
}

function showToast(message) {
  toastBox.textContent = message;
  toastBox.classList.add("show");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toastBox.classList.remove("show"), 2600);
}

function showConfirm(message) {
  modalText.textContent = message;
  modal.hidden = false;
}

function closeConfirm() {
  modal.hidden = true;
}

function drawChart(range = activeRange) {
  const canvas = document.getElementById("trafficChart");
  if (!canvas) return;

  const chartBg = cssVar("--chart-bg") || "#0d1415";
  const chartGrid = cssVar("--chart-grid") || "#263334";
  const muted = cssVar("--muted") || "#778683";
  const green = cssVar("--green") || "#65e8b5";
  const isLight = document.body.dataset.theme === "light";
  const ctx = canvas.getContext("2d");
  const rect = canvas.getBoundingClientRect();
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.floor(rect.width * dpr);
  canvas.height = Math.floor(280 * dpr);
  ctx.scale(dpr, dpr);

  const width = rect.width;
  const height = 280;
  const padding = { left: 52, right: 20, top: 22, bottom: 42 };
  const data = chartSets[range];
  const max = Math.max(...data.values, 10);
  const innerW = width - padding.left - padding.right;
  const innerH = height - padding.top - padding.bottom;

  ctx.clearRect(0, 0, width, height);
  ctx.fillStyle = chartBg;
  ctx.fillRect(0, 0, width, height);

  ctx.strokeStyle = chartGrid;
  ctx.lineWidth = 1;
  ctx.font = "12px system-ui";
  ctx.fillStyle = muted;

  for (let i = 0; i <= 4; i += 1) {
    const y = padding.top + (innerH / 4) * i;
    const value = Math.round(max - (max / 4) * i);
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(width - padding.right, y);
    ctx.stroke();
    ctx.fillText(`${value} GB`, 8, y + 4);
  }

  const points = data.values.map((value, index) => {
    const x = padding.left + (innerW / (data.values.length - 1)) * index;
    const y = padding.top + innerH - (value / max) * innerH;
    return { x, y, value, label: data.labels[index] };
  });

  const gradient = ctx.createLinearGradient(0, padding.top, 0, height - padding.bottom);
  gradient.addColorStop(0, isLight ? "rgba(8, 127, 97, .2)" : "rgba(101, 232, 181, .28)");
  gradient.addColorStop(1, isLight ? "rgba(8, 127, 97, 0)" : "rgba(101, 232, 181, 0)");
  ctx.beginPath();
  points.forEach((point, index) => {
    if (index === 0) ctx.moveTo(point.x, point.y);
    else ctx.lineTo(point.x, point.y);
  });
  ctx.lineTo(points[points.length - 1].x, height - padding.bottom);
  ctx.lineTo(points[0].x, height - padding.bottom);
  ctx.closePath();
  ctx.fillStyle = gradient;
  ctx.fill();

  ctx.beginPath();
  points.forEach((point, index) => {
    if (index === 0) ctx.moveTo(point.x, point.y);
    else ctx.lineTo(point.x, point.y);
  });
  ctx.strokeStyle = green;
  ctx.lineWidth = 2;
  ctx.stroke();

  points.forEach((point) => {
    ctx.beginPath();
    ctx.arc(point.x, point.y, 4, 0, Math.PI * 2);
    ctx.fillStyle = green;
    ctx.fill();
  });

  ctx.fillStyle = muted;
  points.forEach((point, index) => {
    if (index === 0 || index === points.length - 1 || index % 2 === 0) {
      ctx.fillText(point.label, point.x - 16, height - 14);
    }
  });

  canvas.dataset.points = JSON.stringify(points);
}

document.addEventListener("click", (event) => {
  const targetButton = event.target.closest("[data-target]");
  if (targetButton) {
    openPage(targetButton.dataset.target);
  }

  const toastButton = event.target.closest("[data-toast]");
  if (toastButton) {
    showToast(toastButton.dataset.toast);
  }

  const confirmButton = event.target.closest("[data-confirm]");
  if (confirmButton) {
    showConfirm(confirmButton.dataset.confirm);
  }

  const chartButton = event.target.closest("[data-chart-range]");
  if (chartButton) {
    activeRange = chartButton.dataset.chartRange;
    document.querySelectorAll("[data-chart-range]").forEach((button) => {
      button.classList.toggle("active", button === chartButton);
    });
    drawChart(activeRange);
  }

  const codeButton = event.target.closest("[data-code-tab]");
  if (codeButton) {
    document.querySelectorAll("[data-code-tab]").forEach((button) => {
      button.classList.toggle("active", button === codeButton);
    });
    document.querySelector("[data-code-output]").textContent = codeSamples[codeButton.dataset.codeTab];
  }

  const logFilter = event.target.closest("[data-log-filter]");
  if (logFilter) {
    const filter = logFilter.dataset.logFilter;
    document.querySelectorAll("[data-log-filter]").forEach((button) => {
      button.classList.toggle("active", button === logFilter);
    });
    document.querySelectorAll("[data-log-type]").forEach((entry) => {
      entry.hidden = filter !== "all" && entry.dataset.logType !== filter;
    });
  }

  const themeButton = event.target.closest("[data-theme-toggle]");
  if (themeButton) {
    const nextTheme = document.body.dataset.theme === "light" ? "dark" : "light";
    applyTheme(nextTheme);
  }
});

menuToggle?.addEventListener("click", () => {
  menu.classList.toggle("open");
});

modalClose?.addEventListener("click", closeConfirm);
modalOk?.addEventListener("click", () => {
  closeConfirm();
  showToast("操作已加入执行队列。");
});

document.getElementById("trafficChart")?.addEventListener("mousemove", (event) => {
  const canvas = event.currentTarget;
  const tip = document.querySelector("[data-chart-tip]");
  const points = JSON.parse(canvas.dataset.points || "[]");
  if (!points.length) return;

  const rect = canvas.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const nearest = points.reduce((best, point) => {
    return Math.abs(point.x - x) < Math.abs(best.x - x) ? point : best;
  }, points[0]);

  tip.hidden = false;
  tip.style.left = `${Math.min(rect.width - 160, Math.max(10, nearest.x + 8))}px`;
  tip.style.top = `${Math.max(12, nearest.y - 52)}px`;
  tip.innerHTML = `<strong>${nearest.label}</strong><br>消耗 ${nearest.value} GB`;
});

document.getElementById("trafficChart")?.addEventListener("mouseleave", () => {
  document.querySelector("[data-chart-tip]").hidden = true;
});

window.addEventListener("resize", () => drawChart(activeRange));
applyTheme(localStorage.getItem("cdt-control-plane-theme") || "dark");
drawChart(activeRange);
