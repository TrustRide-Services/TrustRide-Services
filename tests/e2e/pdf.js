// Print the report HTML to an A4 PDF and screenshot the acceptance matrix.
const { chromium } = require("playwright");
const { pathToFileURL } = require("url");
(async () => {
  const [html, pdf, png] = process.argv.slice(2);
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1100, height: 900 } });
  await p.goto(pathToFileURL(html).href, { waitUntil: "networkidle" });
  await p.pdf({ path: pdf, format: "A4", printBackground: true, margin: { top: "14mm", bottom: "14mm", left: "12mm", right: "12mm" } });
  const m = p.locator("table").nth(1);
  await m.scrollIntoViewIfNeeded();
  await m.screenshot({ path: png });
  await b.close();
})();
