import { readFile, writeFile } from "node:fs/promises";

const templatePath = new URL("../WhoAmI v5.template.html", import.meta.url);
const logicPath = new URL("../WhoAmI v5.logic.js", import.meta.url);
const dcPath = new URL("../WhoAmI v5.dc.html", import.meta.url);
const livePath = new URL("../WhoAmI v5 · Persome Live.html", import.meta.url);

function camelToKebab(value) {
  return value.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
}

function compileBodyAttributes(markup) {
  return markup.replace(
    /\b((?:on|view)[A-Z][A-Za-z]*)=/g,
    (_, attribute) => `sc-camel-${camelToKebab(attribute)}=`,
  );
}

function serializeTemplate(value) {
  return JSON.stringify(value).replace(/<\/script/gi, "<\\/script");
}

const [sourceTemplate, logic, currentDc, liveWrapper] = await Promise.all([
  readFile(templatePath, "utf8"),
  readFile(logicPath, "utf8"),
  readFile(dcPath, "utf8"),
  readFile(livePath, "utf8"),
]);

const helmetStart = sourceTemplate.indexOf("<helmet>");
const helmetEnd = sourceTemplate.indexOf("</helmet>");
const bodyStart = sourceTemplate.indexOf(
  '<div style="position:fixed;inset:0;overflow:hidden;',
);
if (helmetStart < 0 || helmetEnd < 0 || bodyStart < 0) {
  throw new Error("The source template is missing its helmet or root body.");
}
const helmet = sourceTemplate.slice(helmetStart + "<helmet>".length, helmetEnd);
const body = sourceTemplate.slice(bodyStart).trimEnd();

const scriptOpenMatch = currentDc.match(
  /<script\s+data-dc-script(?:=""|)\s+data-props="[^"]*"[^>]*>/,
);
if (!scriptOpenMatch) {
  throw new Error("The DC source is missing its component script metadata.");
}
const dcDocument = [
  "<!DOCTYPE html>",
  "<html>",
  "<head>",
  '<meta charset="utf-8">',
  '<meta name="viewport" content="width=device-width, initial-scale=1">',
  helmet.trim(),
  "</head>",
  "<body>",
  "<x-dc>",
  body,
  "</x-dc>",
  scriptOpenMatch[0],
  logic.trimEnd(),
  "</script>",
  "</body>",
  "</html>",
  "",
].join("\n");

const payloadTag = '<script type="__bundler/template">';
const payloadStart = liveWrapper.indexOf(payloadTag);
const payloadContentStart = payloadStart + payloadTag.length;
const payloadEnd = liveWrapper.indexOf("</script>", payloadContentStart);
if (payloadStart < 0 || payloadEnd < 0) {
  throw new Error("The live wrapper is missing its bundled template payload.");
}
let embedded = JSON.parse(
  liveWrapper.slice(payloadContentStart, payloadEnd).trim(),
);
const embeddedBodyStart = embedded.indexOf(
  '<div style="position:fixed;inset:0;overflow:hidden;',
);
const embeddedBodyEnd = embedded.indexOf("\n</x-dc>", embeddedBodyStart);
const embeddedLogicStart = embedded.indexOf("const PX =");
const embeddedLogicEnd = embedded.indexOf("\n</script>", embeddedLogicStart);
if (
  embeddedBodyStart < 0 ||
  embeddedBodyEnd < 0 ||
  embeddedLogicStart < 0 ||
  embeddedLogicEnd < 0
) {
  throw new Error("The live bundle does not match the expected V5 structure.");
}

embedded = [
  embedded.slice(0, embeddedBodyStart),
  compileBodyAttributes(body),
  embedded.slice(embeddedBodyEnd, embeddedLogicStart),
  logic.trimEnd(),
  embedded.slice(embeddedLogicEnd),
].join("");
if (!embedded.includes('/src/client/active-model-store.js')) {
  embedded = embedded.replace(
    "</head>",
    '<script src="/src/client/active-model-store.js"></script>\n</head>',
  );
}

let nextWrapper = [
  liveWrapper.slice(0, payloadContentStart),
  "\n",
  serializeTemplate(embedded),
  "\n",
  liveWrapper.slice(payloadEnd),
].join("");
const outerHead = nextWrapper.slice(0, payloadStart);
if (!outerHead.includes('/src/client/active-model-store.js')) {
  nextWrapper = nextWrapper.replace(
    "</head>",
    '  <script src="/src/client/active-model-store.js"></script>\n</head>',
  );
}

await Promise.all([
  writeFile(dcPath, dcDocument, "utf8"),
  writeFile(livePath, nextWrapper, "utf8"),
]);

console.log("Synced template + logic into DC source and live bundle.");
