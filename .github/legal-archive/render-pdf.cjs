// Renders an archived MDX (frontmatter stripped) to PDF. Usage: render-pdf.cjs <archive-dir>/<version-id>
// Needs `marked` and `playwright-core` resolvable (NODE_PATH) and a Chromium binary (CHROMIUM_PATH).
const fs = require('fs');
const { marked } = require('marked');
const { chromium } = require('playwright-core');

(async () => {
  const dir = process.argv[2];
  const raw = fs.readFileSync(`${dir}/source.mdx`, 'utf8');
  const fm = raw.match(/^---\n([\s\S]*?)\n---\n/);
  const title = fm && (fm[1].match(/^title:\s*"?(.*?)"?\s*$/m) || [])[1];
  const body = marked.parse(raw.replace(/^---\n[\s\S]*?\n---\n/, ''));
  const html = `<!doctype html><meta charset="utf-8"><style>body{font:11pt/1.45 sans-serif;margin:0}table{border-collapse:collapse}td,th{border:1px solid #888;padding:3px 6px}</style>${title ? `<h1>${title}</h1>` : ''}${body}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH });
  const page = await browser.newPage();
  await page.setContent(html);
  await page.pdf({ path: `${dir}/rendered.pdf`, format: 'A4', margin: { top: '20mm', bottom: '20mm', left: '18mm', right: '18mm' } });
  await browser.close();
})();
