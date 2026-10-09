const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const root = path.resolve(__dirname, "..");
const runtime =
  process.env.PACKAGE_INFO_TYPE_RUNTIME || "/tmp/package-info-type-runtime";
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "package-info-types-"));
try {
  const config = {
    compilerOptions: {
      allowJs: true,
      checkJs: true,
      noEmit: true,
      strict: true,
      target: "ES2024",
      module: "NodeNext",
      moduleResolution: "NodeNext",
      baseUrl: root,
      paths: {
        semver: [path.join(runtime, "node_modules/@types/semver/index.d.ts")],
        picomatch: [
          path.join(runtime, "node_modules/@types/picomatch/index.d.ts"),
        ],
        "*": [
          path.join(runtime, "node_modules", "*"),
          path.join(runtime, "node_modules", "@types", "*"),
        ],
      },
      typeRoots: [path.join(runtime, "node_modules", "@types")],
      types: ["node"],
    },
    include: [
      path.join(root, "scripts", "**", "*.cjs"),
      path.join(root, "scripts", "**", "*.d.ts"),
      path.join(root, "tests", "*.cjs"),
    ],
  };
  const filename = path.join(temporary, "tsconfig.json");
  fs.writeFileSync(filename, JSON.stringify(config));
  const result = spawnSync(
    process.execPath,
    [
      path.join(runtime, "node_modules", "typescript", "lib", "tsc.js"),
      "-p",
      filename,
    ],
    { encoding: "utf8" },
  );
  process.stdout.write(result.stdout || "");
  process.stderr.write(result.stderr || "");
  if (result.status !== 0) process.exitCode = 1;
  else console.log("package-info: strict JSDoc type check passed");
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
