import { join, normalize } from "node:path";

const root = normalize(join(import.meta.dir, "..", "ui"));

function resolveUiPath(pathname: string): string | null {
  const decoded = decodeURIComponent(pathname);
  if (decoded.includes("\0")) return null;
  const rel = decoded === "/" || decoded === "" ? "index.html" : decoded.replace(/^\//, "");
  if (rel.includes("..")) return null;
  const full = normalize(join(root, rel));
  if (!full.startsWith(root)) return null;
  return full;
}

const port = Number(process.env.PORT) || 5173;
const host = process.env.HOST || "127.0.0.1";

Bun.serve({
  port,
  hostname: host,
  async fetch(req) {
    const url = new URL(req.url);
    const target = resolveUiPath(url.pathname);
    if (!target) {
      return new Response("Bad path", { status: 400 });
    }
    const file = Bun.file(target);
    if (!(await file.exists())) {
      return new Response("Not Found", { status: 404 });
    }
    return new Response(file, {
      headers: {
        "Cache-Control": "no-store",
      },
    });
  },
});

const base = `http://${host}:${port}`;
console.log(`
  es_admin UI dev
  ${base}/?preview=1&debug=1
`);
