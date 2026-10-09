export type Manager = "npm" | "yarn" | "pnpm";
export type ErrorKind =
  "auth" | "not_found" | "timeout" | "metadata" | "network";
export interface Declaration {
  name: string;
  spec: string;
  kind: "range" | "tag" | "local" | "unsupported";
  target?: string;
  range?: string;
  reason?: string;
  section?: string;
  installed?: Installed;
}
export interface Installed {
  state?: "installed" | "unknown" | "not_applicable";
  version?: string;
  reason?: string;
}
export interface Metadata {
  versions: string[];
  "dist-tags": Record<string, string>;
}
export interface Comparison {
  wanted?: string;
  latest?: string;
  status: "unknown" | "unavailable" | "current" | "update" | "major";
  checked_at?: number;
}
export interface Manifest {
  name?: string;
  version?: string;
  packageManager?: string;
  workspaces?: string[] | { packages?: string[] };
  dependencies?: Record<string, unknown>;
  devDependencies?: Record<string, unknown>;
  optionalDependencies?: Record<string, unknown>;
  peerDependencies?: Record<string, unknown>;
  overrides?: unknown;
  resolutions?: unknown;
}
export interface InspectInput {
  path: string;
  manifest: string;
  managers?: Record<string, string>;
  override?: string;
  environment_hash?: string;
  user_config?: string;
}
export interface Context {
  dir: string;
  root: string;
  manager?: string;
  major?: number;
  expected_major?: number;
  marker?: string;
  error?: string;
  fingerprint: string;
  registry_fingerprint: string;
  pnp: boolean;
  custom_plugins: boolean;
  overrides: boolean;
  dependencies: (Declaration & { installed: Installed })[];
}
export interface AuthConfig {
  npmRegistryServer?: string;
  npmAuthToken?: string | null;
  npmAuthIdent?: string | null;
  npmAlwaysAuth?: boolean;
}
export interface ManagerConfig extends AuthConfig {
  [key: string]: unknown;
  registry?: string;
  npmScopes?: Record<string, AuthConfig>;
  npmRegistries?: Record<string, AuthConfig>;
  unsafeHttpWhitelist?: string[];
  enableStrictSsl?: boolean;
  httpProxy?: string;
  httpsProxy?: string;
  networkConcurrency?: number;
  networkSettings?: Record<string, unknown>;
  enableOfflineMode?: boolean;
  enableNetwork?: boolean;
  offline?: boolean;
}
export interface FetchOptions {
  [key: string]: unknown;
  registry: string;
  forceAuth?: { token?: string; auth?: string };
  signal?: AbortSignal;
  strictSSL?: boolean;
  proxy?: string;
  httpsProxy?: string;
  maxSockets?: number;
}
export type Fetch = (
  url: string,
  options: FetchOptions & { signal: AbortSignal },
) => Promise<unknown>;
export interface Client {
  key: string;
  fetch: { json: Fetch };
  options: (name: string) => FetchOptions;
  enabled: boolean;
  concurrency?: unknown;
}
export interface ConfigureInput {
  npm_path: string;
  context: Partial<Context>;
  environment?: NodeJS.ProcessEnv;
  exports?: Record<string, string | undefined>;
}
export interface NativeConfig {
  load(): Promise<void>;
  list: ManagerConfig[];
  flat: ManagerConfig;
}
export interface NpmLibraries {
  root: string;
  load(name: string): unknown;
  fetch: { json: Fetch };
}
export interface CacheEntry {
  time: number;
  metadata?: Metadata;
  error?: string;
  kind?: ErrorKind;
  cached?: boolean;
}
export interface Storage {
  read(key: string): unknown;
  write(key: string, entry: CacheEntry): void;
}
export interface RuntimeSettings {
  globalLimit: number;
  projectLimit: number;
  timeout: number;
  ttl: number;
  retry: number;
  memoryLimit: number;
  disk: boolean;
  diskLimit: number;
  cleanupInterval: number;
  clientTTL: number;
  clientLimit: number;
}
export interface NetworkOptions extends Partial<RuntimeSettings> {
  cacheDir?: string;
}
export interface NetworkDependencies extends NetworkOptions {
  storage: Storage;
  now(): number;
  digest(value: string): string;
}
export interface NetworkTask {
  project: string;
  signal: AbortSignal;
  run(): Promise<CacheEntry>;
  resolve(value: CacheEntry): void;
  reject(error: unknown): void;
  limit: number;
}
export interface NetworkContext {
  root: string;
  dependencies: Declaration[];
}
export interface RecordResult {
  name: string;
  section?: string;
  result?: Comparison;
  error?: string;
  kind?: ErrorKind;
  age_ms: number;
  cached: boolean;
}
export interface Progress {
  records: RecordResult[];
  completed: number;
  total: number;
}
export interface Request {
  id: number;
  method: string;
  input: Record<string, unknown>;
}
export interface Response {
  id?: number;
  result?: unknown;
  error?: string;
  done?: boolean;
}
export type HelperRequest =
  | { id: number; method: "inspect"; input: InspectInput }
  | {
      id: number;
      method: "compare";
      input: { dep: Declaration; stdout: string };
    }
  | { id: number; method: "configure"; input: ConfigureInput }
  | {
      id: number;
      method: "check";
      input: { client: string; context: Context; force?: boolean };
    }
  | { method: "cancel"; id?: number; input: { id: number } };
