const fs = require("fs");
const path = require("path");
const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, Table, TableRow, TableCell,
  WidthType, ShadingType, BorderStyle, AlignmentType, LevelFormat, Footer, PageNumber,
} = require("docx");
const C = require(process.argv[3] || "./completion_content.js");

const OUT = process.argv[2];
const BASE = C.base;
fs.mkdirSync(OUT, { recursive: true });

// status words that get a coloured pill
const STATUS = {
  GREEN: "ok", AMBER: "warn", RED: "bad", PASS: "ok", "N/A": "na", DONE: "ok", "NOT PASS": "bad",
  "CODE REMAINING": "bad", "CONFIGURATION REMAINING": "warn", "PRODUCTION CREDENTIAL REQUIRED": "warn",
  "REAL-WORLD RESOURCE REQUIRED": "warn", "FOUNDER DECISION REQUIRED": "warn", "EXTERNAL PROVIDER DEPENDENCY": "warn",
};

// ---------------------------------------------------------------- Markdown
function mdEsc(s) { return String(s).replace(/\|/g, "\\|"); }
function toMarkdown() {
  const L = [`# ${C.title}`, "", `*${C.subtitle}*`, ""];
  for (const [k, v] of C.meta) L.push(`- **${k}:** ${v}`);
  L.push("");
  for (const b of C.blocks) {
    if (b.h1) L.push(`## ${b.h1}`, "");
    else if (b.h2) L.push(`### ${b.h2}`, "");
    else if (b.p) L.push(b.p, "");
    else if (b.callout) L.push(`> **${b.callout}**`, "");
    else if (b.bullets) { for (const x of b.bullets) L.push(`- ${x}`); L.push(""); }
    else if (b.table) {
      const t = b.table;
      L.push(`| ${t.head.map(mdEsc).join(" | ")} |`, `|${t.head.map(() => "---").join("|")}|`);
      for (const r of t.rows) L.push(`| ${r.map((c) => STATUS[c] ? `**${c}**` : mdEsc(c)).join(" | ")} |`);
      L.push("");
    }
  }
  return L.join("\n");
}

// ---------------------------------------------------------------- HTML
function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
function toHtml() {
  const parts = [];
  for (const b of C.blocks) {
    if (b.h1) parts.push(`<h2>${esc(b.h1)}</h2>`);
    else if (b.h2) parts.push(`<h3>${esc(b.h2)}</h3>`);
    else if (b.p) parts.push(`<p>${esc(b.p)}</p>`);
    else if (b.callout) parts.push(`<aside class="callout">${esc(b.callout)}</aside>`);
    else if (b.bullets) parts.push(`<ul>${b.bullets.map((x) => `<li>${esc(x)}</li>`).join("")}</ul>`);
    else if (b.table) {
      const t = b.table;
      const cols = t.head.length;
      parts.push(`<div class="tw"><table class="c${cols}"><thead><tr>${t.head.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${
        t.rows.map((r) => `<tr>${r.map((c, i) => {
          const s = STATUS[c];
          if (s) return `<td><span class="pill ${s}">${esc(c)}</span></td>`;
          if (i === 0 && /^[GD]\d+$/.test(c)) return `<td class="id">${esc(c)}</td>`;
          return `<td>${esc(c)}</td>`;
        }).join("")}</tr>`).join("")
      }</tbody></table></div>`);
    }
  }
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(C.title)}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Libre+Franklin:wght@400;600;700&family=Source+Serif+4:opsz,wght@8..60,400;8..60,600&display=swap">
<style>
:root{
  --navy:#0B1424; --navy-2:#1B2A44; --gold:#B8862E; --gold-soft:#F2E7C9;
  --ink:#1C2230; --muted:#5B6474; --rule:#D9DEE7; --ground:#FFFFFF; --band:#F5F7FA;
  --ok:#2E6B3E; --ok-bg:#E3F0E6; --warn:#8A5A00; --warn-bg:#FBEFD2; --bad:#A32E2E; --bad-bg:#F7E1E1;
}
*{box-sizing:border-box}
html{background:var(--ground)}
body{margin:0;background:var(--ground);color:var(--ink);font:16px/1.6 "Source Serif 4",Georgia,"Times New Roman",serif}
.wrap{max-width:1020px;margin:0 auto;padding:0 16px 64px}
header.cover{background:var(--navy);color:#fff;padding:48px 16px 36px;border-bottom:4px solid var(--gold)}
header.cover .wrap{padding-bottom:0}
.eyebrow{font:600 12px/1 "Libre Franklin",Arial,sans-serif;letter-spacing:.14em;text-transform:uppercase;color:var(--gold)}
h1{font:700 clamp(28px,4.4vw,40px)/1.15 "Libre Franklin",Arial,sans-serif;margin:12px 0 8px;text-wrap:balance}
.sub{color:#C9D2E3;margin:0 0 24px;max-width:65ch}
dl.meta{display:grid;grid-template-columns:max-content 1fr;gap:6px 20px;margin:0;font-size:14px}
dl.meta dt{font:600 12px/1.6 "Libre Franklin",Arial,sans-serif;letter-spacing:.06em;text-transform:uppercase;color:var(--gold)}
dl.meta dd{margin:0;color:#E6EBF3}
h2{font:700 24px/1.25 "Libre Franklin",Arial,sans-serif;color:var(--navy);margin:48px 0 14px;padding-bottom:8px;border-bottom:2px solid var(--gold);text-wrap:balance}
h3{font:700 17px/1.3 "Libre Franklin",Arial,sans-serif;color:var(--navy-2);margin:30px 0 10px}
p,li{max-width:72ch}
ul{padding-left:22px;display:grid;gap:6px}
.tw{overflow-x:auto;margin:14px 0 8px;border:1px solid var(--rule);border-radius:4px}
table{border-collapse:collapse;width:100%;font:14px/1.45 "Libre Franklin",Arial,sans-serif;font-variant-numeric:tabular-nums}
th{background:var(--navy);color:#fff;text-align:left;font-weight:600;padding:9px 10px;font-size:12px;letter-spacing:.04em;text-transform:uppercase}
td{padding:9px 10px;border-top:1px solid var(--rule);vertical-align:top}
tbody tr:nth-child(even) td{background:var(--band)}
td.id{font-weight:700;color:var(--navy);white-space:nowrap}
table.c5 td:nth-child(5){white-space:nowrap}
table.c6{table-layout:fixed}
table.c6 td,table.c6 th{font-size:11.5px;overflow-wrap:anywhere;word-break:break-word}
table.c6 th:nth-child(1){width:13%} table.c6 th:nth-child(2){width:10%} table.c6 th:nth-child(3){width:20%} table.c6 th:nth-child(4){width:31%} table.c6 th:nth-child(5){width:18%} table.c6 th:nth-child(6){width:8%}
table td{overflow-wrap:anywhere}
table.c6 td:last-child{white-space:nowrap}
table.c14 th,table.c14 td{padding:6px 4px;font-size:11px;text-align:center}
table.c14 th:first-child,table.c14 td:first-child{text-align:left;white-space:nowrap}
table.c14 th{letter-spacing:0;text-transform:none}
table.c14 .pill{padding:1px 5px;font-size:10px}
.pill{display:inline-block;padding:2px 9px;border-radius:999px;font-weight:700;font-size:12px;white-space:nowrap}
.pill.ok{background:var(--ok-bg);color:var(--ok)} .pill.na{background:var(--band);color:var(--muted)} .pill.warn{background:var(--warn-bg);color:var(--warn)} .pill.bad{background:var(--bad-bg);color:var(--bad)}
.callout{margin:28px 0 0;padding:16px 20px;background:var(--gold-soft);border-left:4px solid var(--gold);font-weight:600;color:var(--navy)}
footer{margin-top:48px;padding-top:12px;border-top:1px solid var(--rule);color:var(--muted);font:13px/1.5 "Libre Franklin",Arial,sans-serif}
@media print{
  @page{size:A4;margin:14mm 12mm}
  body{font-size:11pt}
  header.cover{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  th,.pill,.callout,tbody tr:nth-child(even) td{-webkit-print-color-adjust:exact;print-color-adjust:exact}
  h2{break-after:avoid} h3{break-after:avoid} tr{break-inside:avoid}
  .tw{overflow:visible;border:none}
}
</style>
</head>
<body>
<header class="cover"><div class="wrap">
  <div class="eyebrow">${esc(C.eyebrow)}</div>
  <h1>${esc(C.title)}</h1>
  <p class="sub">${esc(C.subtitle)}</p>
  <dl class="meta">${C.meta.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join("")}</dl>
</div></header>
<main class="wrap">
${parts.join("\n")}
<footer>${esc(C.footer)}</footer>
</main>
</body>
</html>`;
}

// ---------------------------------------------------------------- Word
const NAVY = "0B1424", GOLD = "B8862E", INK = "1C2230", BAND = "F5F7FA", RULE = "D9DEE7";
const PILL = { ok: ["2E6B3E", "E3F0E6"], warn: ["8A5A00", "FBEFD2"], bad: ["A32E2E", "F7E1E1"], na: ["5B6474", "F5F7FA"] };
const CONTENT_W = 12240 - 2 * 1080; // US Letter, 0.75in margins

const cellBorders = { top: { style: BorderStyle.SINGLE, size: 4, color: RULE }, bottom: { style: BorderStyle.SINGLE, size: 4, color: RULE },
  left: { style: BorderStyle.SINGLE, size: 4, color: RULE }, right: { style: BorderStyle.SINGLE, size: 4, color: RULE } };

const COLW = { // relative column weights per table width
  2: [1, 2], 3: [1.1, 1, 2.6], 4: [1.3, 1.9, 0.9, 2.6], 5: [0.45, 2.1, 2.1, 2.4, 0.75],
};
function widths(t) {
  let w = t.widths || COLW[t.head.length] || t.head.map(() => 1);
  if (t.head.length === 3 && t.head[0] === "#") w = [0.4, 2.6, 3.0];
  if (t.head.length === 3 && t.head[0] === "Step") w = [1.0, 2.6, 2.2];
  if (t.head.length === 3 && t.head[0] === "Service") w = [1.5, 2.7, 1.6];
  const sum = w.reduce((a, b) => a + b, 0);
  const out = w.map((x) => Math.floor((x / sum) * CONTENT_W));
  out[out.length - 1] += CONTENT_W - out.reduce((a, b) => a + b, 0);
  return out;
}
function docTable(t) {
  const ws = widths(t);
  const hdr = new TableRow({ tableHeader: true, children: t.head.map((h, i) => new TableCell({
    width: { size: ws[i], type: WidthType.DXA }, borders: cellBorders,
    shading: { type: ShadingType.CLEAR, color: "auto", fill: NAVY },
    margins: { top: 80, bottom: 80, left: 100, right: 100 },
    children: [new Paragraph({ children: [new TextRun({ text: h.toUpperCase(), bold: true, color: "FFFFFF", size: 16, font: "Arial" })] })],
  })) });
  const rows = t.rows.map((r, ri) => new TableRow({ cantSplit: true, children: r.map((c, i) => {
    const s = STATUS[c];
    const fill = s ? PILL[s][1] : (ri % 2 ? BAND : "FFFFFF");
    const run = s ? new TextRun({ text: c, bold: true, color: PILL[s][0], size: 17, font: "Arial" })
      : new TextRun({ text: c, size: 17, font: "Arial", color: INK, bold: i === 0 && /^[GD]\d+$/.test(c) });
    return new TableCell({
      width: { size: ws[i], type: WidthType.DXA }, borders: cellBorders,
      shading: { type: ShadingType.CLEAR, color: "auto", fill },
      margins: { top: 70, bottom: 70, left: 100, right: 100 },
      children: [new Paragraph({ children: [run] })],
    });
  }) }));
  return new Table({ width: { size: CONTENT_W, type: WidthType.DXA }, columnWidths: ws, rows: [hdr, ...rows] });
}
function toDocx() {
  const kids = [
    new Paragraph({ children: [new TextRun({ text: C.eyebrow.toUpperCase(), bold: true, color: GOLD, size: 18, font: "Arial" })] }),
    new Paragraph({ spacing: { before: 120, after: 80 }, children: [new TextRun({ text: C.title, bold: true, color: NAVY, size: 44, font: "Arial" })] }),
    new Paragraph({ spacing: { after: 240 }, border: { bottom: { style: BorderStyle.SINGLE, size: 12, color: GOLD, space: 6 } },
      children: [new TextRun({ text: C.subtitle, italics: true, color: "5B6474", size: 22 })] }),
    ...C.meta.map(([k, v]) => new Paragraph({ spacing: { after: 60 }, children: [
      new TextRun({ text: k + ": ", bold: true, color: NAVY, size: 19, font: "Arial" }), new TextRun({ text: v, size: 19, color: INK })] })),
  ];
  for (const b of C.blocks) {
    if (b.h1) kids.push(new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 400, after: 160 },
      border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: GOLD, space: 4 } },
      children: [new TextRun({ text: b.h1, bold: true, color: NAVY, size: 30, font: "Arial" })] }));
    else if (b.h2) kids.push(new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 280, after: 120 },
      children: [new TextRun({ text: b.h2, bold: true, color: NAVY, size: 24, font: "Arial" })] }));
    else if (b.p) kids.push(new Paragraph({ spacing: { after: 140, line: 300 }, children: [new TextRun({ text: b.p, size: 21, color: INK })] }));
    else if (b.callout) kids.push(new Paragraph({ spacing: { before: 280, after: 140 },
      shading: { type: ShadingType.CLEAR, color: "auto", fill: "F2E7C9" },
      border: { left: { style: BorderStyle.SINGLE, size: 24, color: GOLD, space: 8 } },
      children: [new TextRun({ text: b.callout, bold: true, color: NAVY, size: 21 })] }));
    else if (b.bullets) for (const x of b.bullets) kids.push(new Paragraph({ numbering: { reference: "dots", level: 0 },
      spacing: { after: 80, line: 288 }, children: [new TextRun({ text: x, size: 21, color: INK })] }));
    else if (b.table) { kids.push(docTable(b.table)); kids.push(new Paragraph({ spacing: { after: 120 }, children: [] })); }
  }
  return new Document({
    creator: "TrustRide Services", title: C.title, description: C.subtitle,
    styles: { default: { document: { run: { font: "Georgia", size: 21 } } },
      paragraphStyles: [
        { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 30, bold: true, font: "Arial", color: NAVY }, paragraph: { outlineLevel: 0 } },
        { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true, run: { size: 24, bold: true, font: "Arial", color: NAVY }, paragraph: { outlineLevel: 1 } },
      ] },
    numbering: { config: [{ reference: "dots", levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
      style: { paragraph: { indent: { left: 540, hanging: 300 } } } }] }] },
    sections: [{
      properties: { page: { size: { width: 12240, height: 15840 }, margin: { top: 1080, bottom: 1080, left: 1080, right: 1080 } } },
      footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [
        new TextRun({ text: C.title + " — page ", size: 16, color: "5B6474" }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, color: "5B6474" })] })] }) },
      children: kids,
    }],
  });
}

(async () => {
  fs.writeFileSync(path.join(OUT, BASE + ".md"), toMarkdown(), "utf8");
  if (process.argv[4] === "landscape") {}
  fs.writeFileSync(path.join(OUT, BASE + ".html"), toHtml(), "utf8");
  fs.writeFileSync(path.join(OUT, BASE + ".docx"), await Packer.toBuffer(toDocx()));
  console.log("written md, html, docx to", OUT);
})();
