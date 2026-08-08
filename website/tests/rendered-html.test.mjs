import assert from "node:assert/strict";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("https://who-am-i.example/", {
      headers: { accept: "text/html", host: "who-am-i.example" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the Who Am I release page", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<html[^>]+lang="zh-CN"/i);
  assert.match(html, /<title>Who Am I — 你的 Personal Model，只属于你<\/title>/i);
  assert.match(html, /你的 Personal Model/);
  assert.match(html, /正在读取 GitHub Release/);
  assert.match(html, /NO SHARED CARD/);
  assert.match(html, /下载的是软件，不是任何人的记忆/);
  assert.match(html, /GitHub 是唯一发布源/);
  assert.match(html, /https:\/\/who-am-i\.example\/og\.png/);
  assert.doesNotMatch(html, /codex-preview|react-loading-skeleton|Cecilia|Lin · @lin/);
});
