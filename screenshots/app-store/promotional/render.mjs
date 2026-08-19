import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdirSync, statSync, unlinkSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, "../en-US/promotional");
const masters = path.join(output, "masters");
const chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

mkdirSync(output, { recursive: true });
mkdirSync(masters, { recursive: true });

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function render(mode, width, height, file) {
    const url = `file://${path.join(here, "index.html")}?mode=${mode}`;
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
        `--window-size=${width},${height}`,
        `--user-data-dir=/tmp/moro-appstore-${process.pid}-${mode}`,
        `--screenshot=${file}`,
        url,
    ], { detached: true, stdio: "ignore" });
    child.unref();

    const deadline = Date.now() + 15_000;
    while (Date.now() < deadline) {
        if (existsSync(file) && statSync(file).size > 1_000) {
            await sleep(250);
            try { process.kill(-child.pid, "SIGTERM"); } catch {}
            return;
        }
        await sleep(100);
    }

    try { process.kill(-child.pid, "SIGKILL"); } catch {}
    throw new Error(`Chrome did not render ${mode} within 15 seconds`);
}

function crop(source, x, destination) {
    execFileSync("magick", [
        source,
        "-crop", `1320x2868+${x}+0`,
        "+repage",
        "-strip",
        destination,
    ], { stdio: "inherit" });
}

const heroMaster = path.join(masters, "01-03-hero-master.png");
const composeMaster = path.join(masters, "07-08-compose-master.png");

await render("hero", 3960, 2868, heroMaster);
crop(heroMaster, 0, path.join(output, "01-moro.png"));
crop(heroMaster, 1320, path.join(output, "02-moro.png"));
crop(heroMaster, 2640, path.join(output, "03-moro.png"));

for (const slide of [4, 5, 6]) {
    await render(String(slide), 1320, 2868, path.join(output, `${String(slide).padStart(2, "0")}-moro.png`));
}

await render("compose", 2640, 2868, composeMaster);
crop(composeMaster, 0, path.join(output, "07-moro.png"));
crop(composeMaster, 1320, path.join(output, "08-moro.png"));

for (const slide of [9, 10]) {
    await render(String(slide), 1320, 2868, path.join(output, `${String(slide).padStart(2, "0")}-moro.png`));
}

const firstRow = path.join(masters, "preview-row-1.png");
const secondRow = path.join(masters, "preview-row-2.png");
const files = Array.from({ length: 10 }, (_, index) =>
    path.join(output, `${String(index + 1).padStart(2, "0")}-moro.png`)
);

execFileSync("magick", [
    ...files.slice(0, 5).flatMap((file) => ["(", file, "-resize", "264x574", ")"]),
    "+append", "-strip", firstRow,
]);
execFileSync("magick", [
    ...files.slice(5).flatMap((file) => ["(", file, "-resize", "264x574", ")"]),
    "+append", "-strip", secondRow,
]);
execFileSync("magick", [firstRow, secondRow, "-append", "-strip", path.join(masters, "contact-sheet.png")]);
