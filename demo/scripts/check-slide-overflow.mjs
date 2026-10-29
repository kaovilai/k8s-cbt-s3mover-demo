#!/usr/bin/env node
/**
 * Fail when slide content spills outside the slide canvas.
 *
 * Slidev renders each slide on a 980x552 canvas and then scales it to the
 * viewport, so every slide looks fine at overview zoom while still being cut
 * off for a viewer. This walks the rendered DOM of every slide, compares each
 * element against that slide's own canvas box, and reports the ones that
 * escape it (or get clipped by an ancestor that scrolls/hides).
 *
 * Usage:
 *   node scripts/check-slide-overflow.mjs --url http://localhost:3030
 *   node scripts/check-slide-overflow.mjs --pages 11,17-20
 *
 * Exits 1 when any overflow is found, so CI can gate on it.
 */
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const require = createRequire(resolve(here, "../package.json"));
const { chromium } = require("playwright-chromium");

function parseArgs(argv) {
  const opts = {
    url: "http://localhost:3030",
    pages: null,
    tolerance: 2,
    settle: 1200,
    json: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = () => argv[++i];
    if (a === "--url") opts.url = next();
    else if (a === "--pages") opts.pages = next();
    else if (a === "--tolerance") opts.tolerance = Number(next());
    else if (a === "--settle") opts.settle = Number(next());
    else if (a === "--json") opts.json = true;
    else if (a === "--help" || a === "-h") {
      console.log("usage: check-slide-overflow.mjs [--url URL] [--pages 1,3-5] [--tolerance PX] [--settle MS] [--json]");
      process.exit(0);
    } else {
      console.error(`unknown argument: ${a}`);
      process.exit(2);
    }
  }
  return opts;
}

function expandPages(spec, fallbackCount) {
  if (!spec) return Array.from({ length: fallbackCount }, (_, i) => i + 1);
  const out = [];
  for (const part of spec.split(",")) {
    const chunk = part.trim();
    if (!chunk) continue;
    const [from, to] = chunk.split("-").map(Number);
    if (Number.isNaN(from)) continue;
    const end = Number.isNaN(to) ? from : to;
    for (let n = from; n <= end; n++) out.push(n);
  }
  return out;
}

/** Runs in the page: collect every box that escapes, or is clipped by, its slide. */
function measureSlide(tolerance) {
  const pages = [...document.querySelectorAll(".slidev-page")];
  const pageEl = pages.find((p) => p.getBoundingClientRect().width > 0);
  if (!pageEl) return { found: false, issues: [] };

  const canvas = pageEl.querySelector(".slidev-slide-content") || pageEl;
  const box = canvas.getBoundingClientRect();
  const issues = [];

  const label = (el) => {
    const tag = el.tagName.toLowerCase();
    const cls = (el.getAttribute("class") || "").trim().split(/\s+/).slice(0, 3).join(".");
    const text = (el.textContent || "").trim().replace(/\s+/g, " ").slice(0, 60);
    return `${tag}${cls ? "." + cls : ""}${text ? ` "${text}"` : ""}`;
  };

  const escapes = (r) => {
    const sides = [];
    if (r.left < box.left - tolerance) sides.push(`left ${Math.round(box.left - r.left)}`);
    if (r.right > box.right + tolerance) sides.push(`right ${Math.round(r.right - box.right)}`);
    if (r.top < box.top - tolerance) sides.push(`top ${Math.round(box.top - r.top)}`);
    if (r.bottom > box.bottom + tolerance) sides.push(`bottom ${Math.round(r.bottom - box.bottom)}`);
    return sides;
  };

  const clippingAncestor = (el) => {
    let node = el.parentElement;
    while (node && node !== canvas) {
      const s = getComputedStyle(node);
      if (s.overflow !== "visible" || s.overflowX !== "visible" || s.overflowY !== "visible") {
        return node;
      }
      node = node.parentElement;
    }
    return null;
  };

  const visit = (el) => {
    for (const child of el.children) {
      const s = getComputedStyle(child);
      if (s.display === "none" || s.visibility === "hidden") continue;
      const r = child.getBoundingClientRect();
      if (r.width > 0 || r.height > 0) {
        const sides = escapes(r);
        if (sides.length) {
          const clip = clippingAncestor(child);
          issues.push({
            kind: clip ? "clipped" : "escapes",
            what: label(child),
            sides,
            clippedBy: clip ? label(clip) : null,
          });
        }
      }
      // Mermaid draws into a shadow root, so light-DOM boxes cannot see it.
      if (child.shadowRoot) {
        const svg = child.shadowRoot.querySelector("svg");
        if (svg) {
          const sr = svg.getBoundingClientRect();
          const sides = escapes(sr);
          if (sides.length) {
            issues.push({
              kind: "diagram",
              what: `${label(child)} svg ${Math.round(sr.width)}x${Math.round(sr.height)}`,
              sides,
              clippedBy: null,
            });
          }
        }
      }
      visit(child);
    }
  };

  visit(canvas);
  return { found: true, canvas: { w: Math.round(box.width), h: Math.round(box.height) }, issues };
}

const opts = parseArgs(process.argv.slice(2));
const base = opts.url.replace(/\/$/, "");

let browser;
try {
  browser = await chromium.launch({ channel: "chrome", headless: true });
} catch (err) {
  console.error(`could not launch Chrome: ${err.message.split("\n")[0]}`);
  process.exit(3);
}
const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
const page = await context.newPage();

// The dev server may still be booting (CI starts it in the background).
let loaded = false;
for (let attempt = 0; attempt < 30 && !loaded; attempt++) {
  try {
    await page.goto(`${base}/1?clicks=99`, { waitUntil: "networkidle", timeout: 30000 });
    loaded = true;
  } catch {
    await page.waitForTimeout(2000);
  }
}
if (!loaded) {
  console.error(`could not reach ${base} - is the Slidev dev server running?`);
  await browser.close();
  process.exit(2);
}

// Slidev mounts slide components progressively (a couple at first, the rest a
// moment later), so wait for the count to stop moving before trusting it.
let totalPages = 0;
let stable = 0;
for (let i = 0; i < 40; i++) {
  await page.waitForTimeout(500);
  const count = await page.evaluate(
    () => document.querySelectorAll(".slidev-page").length,
  );
  stable = count === totalPages ? stable + 1 : 0;
  totalPages = count;
  if (stable >= 2) break;
}
if (totalPages < 2) {
  console.error("could not find any rendered slides - is the dev server running?");
  await browser.close();
  process.exit(2);
}

const failures = [];
for (const n of expandPages(opts.pages, totalPages)) {
  if (n < 1 || n > totalPages) continue;
  // Navigate client-side so each slide does not trigger a full reload.
  await page.evaluate((target) => window.__slidev__?.nav?.go?.(target), n);
  await page
    .waitForFunction(
      (target) => {
        const el = document.querySelector(`.slidev-page-${target}`);
        return !!el && el.getBoundingClientRect().width > 0;
      },
      n,
      { timeout: 15000 },
    )
    .catch(() => {});
  await page.waitForTimeout(opts.settle);
  const result = await page.evaluate(measureSlide, opts.tolerance);
  if (result.issues.length) failures.push({ slide: n, issues: result.issues });
}

await browser.close();

if (opts.json) {
  console.log(JSON.stringify({ totalPages, failures }, null, 2));
} else {
  console.log(`checked ${totalPages} slides at ${base}`);
  if (!failures.length) {
    console.log("OK: no slide content escapes its canvas");
  } else {
    for (const { slide, issues } of failures) {
      console.log(`\nslide ${slide}: ${issues.length} issue(s)`);
      for (const i of issues) {
        const where = i.clippedBy ? ` [clipped by ${i.clippedBy}]` : "";
        console.log(`  ${i.kind}: ${i.what}${where} -> ${i.sides.join(", ")}`);
      }
    }
  }
}
process.exit(failures.length ? 1 : 0);
