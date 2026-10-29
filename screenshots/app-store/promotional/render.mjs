import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, statSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// Usage: node render.mjs [zh-Hans,en-US]
// Reads the real captures from ../<locale>/iphone/ and writes ../<locale>/promotional/.
const here = path.dirname(fileURLToPath(import.meta.url));
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const locales = (process.argv[2] || "zh-Hans,en-US").split(",").filter(Boolean);

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function render(locale, mode, width, height, file) {
    const url = `file://${path.join(here, "index.html")}?lang=${locale}&mode=${mode}`;
    if (existsSync(file)) unlinkSync(file);

    const child = spawn(chrome, [
        "--headless=new",
        "--hide-scrollbars",
        "--disable-gpu",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-domain-reliability",
        "--disable-extensions",
        "--disable-features=DefaultApps,OptimizationHints,MediaRouter",
        "--disable-sync",
        "--metrics-recording-only",
        "--no-first-run",
        "--no-default-browser-check",
        "--allow-file-access-from-files",
        "--force-device-scale-factor=1",
        "--virtual-time-budget=3000",
        `--window-size=${width},${height}`,
        `--user-data-dir=/tmp/moro-appstore-${process.pid}-${locale}-${mode}`,
        `--screenshot=${file}`,
        url,
    ], { detached: true, stdio: "ignore" });
    child.unref();

    const deadline = Date.now() + 20_000;
    while (Date.now() < deadline) {
        if (existsSync(file) && statSync(file).size > 1_000) {
            await sleep(250);
            try { process.kill(-child.pid, "SIGTERM"); } catch {}
            return;
        }
        await sleep(100);
    }

    try { process.kill(-child.pid, "SIGKILL"); } catch {}
    throw new Error(`Chrome did not render ${locale}/${mode} within 20 seconds`);
}

// App Store Connect rejects screenshots with an alpha channel.
function finish(source, destination, x = null) {
    const crop = x === null ? [] : ["-crop", `1320x2868+${x}+0`, "+repage"];
    execFileSync("magick", [
        source, ...crop,
        "-background", "white", "-alpha", "remove", "-alpha", "off",
        "-strip", destination,
    ], { stdio: "inherit" });
}

for (const locale of locales) {
    const output = path.resolve(here, `../${locale}/promotional`);
    const masters = path.join(output, "masters");
    mkdirSync(masters, { recursive: true });
    const name = (slide) => path.join(output, `${String(slide).padStart(2, "0")}-moro.png`);

    const heroMaster = path.join(masters, "01-03-hero-master.png");
    await render(locale, "hero", 3960, 2868, heroMaster);
    [0, 1, 2].forEach((index) => finish(heroMaster, name(index + 1), index * 1320));

    for (const slide of [4, 5, 6, 9, 10]) {
        const raw = path.join(masters, `${String(slide).padStart(2, "0")}-raw.png`);
        await render(locale, String(slide), 1320, 2868, raw);
        finish(raw, name(slide));
        unlinkSync(raw);
    }

    const composeMaster = path.join(masters, "07-08-compose-master.png");
    await render(locale, "compose", 2640, 2868, composeMaster);
    finish(composeMaster, name(7), 0);
    finish(composeMaster, name(8), 1320);

    const files = Array.from({ length: 10 }, (_, index) => name(index + 1));
    const row = (slice, file) => execFileSync("magick", [
        ...slice.flatMap((f) => ["(", f, "-resize", "264x574", ")"]),
        "+append", "-strip", file,
    ]);
    const firstRow = path.join(masters, "preview-row-1.png");
    const secondRow = path.join(masters, "preview-row-2.png");
    row(files.slice(0, 5), firstRow);
    row(files.slice(5), secondRow);
    execFileSync("magick", [firstRow, secondRow, "-append", "-strip", path.join(masters, "contact-sheet.png")]);
    unlinkSync(firstRow);
    unlinkSync(secondRow);
    console.log(`${locale}: ${files.length} screenshots → ${output}`);
}
