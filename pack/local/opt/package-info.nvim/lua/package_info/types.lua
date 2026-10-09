---@alias PackageInfoEnsureCallback fun(ok?: boolean, error?: string): nil
---@alias PackageInfoResponse fun(value: unknown): nil
---@alias PackageInfoBootstrapCallback fun(error?: string): nil
---@alias PackageInfoValid fun(buf: integer, state: PackageInfoBuffer): boolean
---@alias PackageInfoRender fun(buf: integer, state: PackageInfoBuffer): nil
---@alias PackageInfoManager "npm" | "yarn" | "pnpm"
---@alias PackageInfoCancel fun(): nil
---@alias PackageInfoReply fun(result: unknown, error?: string, done?: boolean): nil
---@alias PackageInfoErrorKind "timeout" | "auth" | "config" | "not_found" | "manager" | "network" | "metadata"
---@alias PackageInfoChunk {[1]: string, [2]: string}
---@alias PackageInfoAnnotations table<integer, PackageInfoChunk[]>

---@class PackageInfoRenderQueue
---@field request PackageInfoRender
---@field cancel fun(buf: integer): nil
---@field pending fun(): integer
---@field teardown PackageInfoCancel
---@alias PackageInfoSection "dependencies" | "devDependencies" | "optionalDependencies" | "peerDependencies"
---@alias PackageInfoDisplayStatus "installed" | "update" | "major" | "unavailable" | "not_found" | "unsupported" | "error"
---@alias PackageInfoTextPosition "eol" | "eol_right_align" | "right_align"
---@alias PackageInfoBorder "none" | "single" | "double" | "rounded" | "solid" | "shadow"

---@class PackageInfoTimeouts
---@field registry integer
---@field manager integer
---@field helper integer
---@field bootstrap integer

---@class PackageInfoConcurrency
---@field http integer
---@field http_per_project integer
---@field cli integer
---@field cli_per_project integer

---@class PackageInfoCacheConfig
---@field ttl integer
---@field retry integer
---@field memory_limit integer
---@field cli_limit integer
---@field disk boolean
---@field disk_limit integer
---@field cleanup_interval integer
---@field client_ttl integer
---@field client_limit integer

---@class PackageInfoFloat
---@field border PackageInfoBorder
---@field focusable boolean
---@field max_width? integer
---@field max_height? integer

---@class PackageInfoDisplay
---@field enabled boolean
---@field statuses PackageInfoDisplayStatus[]
---@field icons {installed: string, update: string, error: string}
---@field prefix string
---@field virt_text_pos PackageInfoTextPosition
---@field float PackageInfoFloat

---@class PackageInfoOptions
---@field managers? table<string, string>
---@field fast_registry? boolean
---@field auto_refresh? boolean | {on_enter?: boolean, on_save?: boolean}
---@field sections? PackageInfoSection[]
---@field exclude? {packages?: string[], projects?: string[]}
---@field timeouts? {registry?: integer, manager?: integer, helper?: integer, bootstrap?: integer}
---@field concurrency? {http?: integer, http_per_project?: integer, cli?: integer, cli_per_project?: integer}
---@field cache? {ttl?: integer, retry?: integer, memory_limit?: integer, cli_limit?: integer, disk?: boolean, disk_limit?: integer, cleanup_interval?: integer, client_ttl?: integer, client_limit?: integer}
---@field display? {enabled?: boolean, statuses?: PackageInfoDisplayStatus[], icons?: {installed?: string, update?: string, error?: string}, prefix?: string, virt_text_pos?: PackageInfoTextPosition, float?: {border?: PackageInfoBorder, focusable?: boolean, max_width?: integer, max_height?: integer}}

---@class PackageInfoConfig
---@field managers table<string, string>
---@field fast_registry boolean
---@field auto_refresh {on_enter: boolean, on_save: boolean}
---@field sections PackageInfoSection[]
---@field exclude {packages: string[], projects: string[]}
---@field timeouts PackageInfoTimeouts
---@field concurrency PackageInfoConcurrency
---@field cache PackageInfoCacheConfig
---@field display PackageInfoDisplay

---@class PackageInfoHost
---@field path string
---@field tick integer
---@field modified boolean

---@class PackageInfoManifestFact
---@field object string
---@field key string
---@field row integer
---@field kind string
---@field top? boolean
---@field section? string

---@class PackageInfoManifest
---@field text string
---@field lines table<string, integer>

---@class PackageInfoInstalled
---@field state? "installed" | "unknown" | "not_applicable"
---@field version? string
---@field reason? string

---@class PackageInfoComparison
---@field wanted? string
---@field latest? string
---@field status "unknown" | "current" | "update" | "major" | "unavailable"
---@field checked_at? number

---@class PackageInfoDependency
---@field name string
---@field spec string
---@field section string
---@field kind "range" | "tag" | "local" | "unsupported"
---@field target? string
---@field range? string
---@field installed? PackageInfoInstalled
---@field result? PackageInfoComparison
---@field reason? string
---@field error? string
---@field error_kind? PackageInfoErrorKind
---@field registry_time? number
---@field cached? boolean

---@class PackageInfoContext
---@field dir string
---@field root string
---@field manager PackageInfoManager
---@field major? integer
---@field expected_major? integer
---@field marker? string
---@field error? string
---@field fingerprint string
---@field registry_fingerprint string
---@field dependencies PackageInfoDependency[]
---@field pnp? boolean
---@field custom_plugins? boolean
---@field overrides? boolean

---@class PackageInfoRecord
---@field name string
---@field section string
---@field result? PackageInfoComparison
---@field error? string
---@field kind? PackageInfoErrorKind
---@field age_ms number
---@field cached? boolean

---@class PackageInfoEvent
---@field reconfigure? boolean
---@field complete? boolean
---@field records? PackageInfoRecord[]
---@field completed? integer
---@field total? integer

---@class PackageInfoConfiguration
---@field fallback? boolean
---@field client? string

---@class PackageInfoTicket
---@field id? integer
---@field cancelled? boolean
---@field timer? PackageInfoCancel
---@field wait? fun(ok?: boolean, error?: string): nil

---@class PackageInfoBuffer
---@field path? string
---@field tick? integer
---@field disabled? boolean
---@field context? PackageInfoContext
---@field lines table<string, integer>
---@field tickets PackageInfoTicket[]
---@field checked_at? number
---@field error? string
---@field backend? string
---@field network? {completed: integer, total: integer}
---@field network_ticket? PackageInfoTicket
---@field client_retries? integer

---@class PackageInfoCacheEntry
---@field time number
---@field stdout? string
---@field error? string
---@field kind? PackageInfoErrorKind

---@class PackageInfoProcessResult
---@field code integer
---@field signal? integer
---@field stdout? string
---@field stderr? string

---@class PackageInfoProcess
---@field kill fun(self: PackageInfoProcess, signal: integer): nil

---@class PackageInfoTask
---@field project string
---@field cwd string
---@field command string[]
---@field timeout? integer
---@field cancelled fun(): boolean
---@field callback fun(result: PackageInfoProcessResult): nil

---@class PackageInfoQueue
---@field active integer
---@field projects table<string, integer>
---@field waiting PackageInfoTask[]
---@field jobs table<PackageInfoTask, {process?: PackageInfoProcess, cancelled?: boolean}>
---@field submit fun(task: PackageInfoTask): nil
---@field cancel PackageInfoCancel
---@field teardown PackageInfoCancel
---@field configure fun(options: PackageInfoConcurrency): nil

---@class PackageInfoHelperAdapter
---@field source string
---@field runtime string
---@field now fun(): number
---@field notify fun(message: string): nil
---@field bootstrap fun(source: string, runtime: string, callback: PackageInfoBootstrapCallback): nil
---@field start fun(runtime: string, response: PackageInfoResponse, exit: PackageInfoCancel): integer
---@field stop fun(job?: integer): nil
---@field schedule fun(delay: integer, callback: PackageInfoCancel): PackageInfoCancel
---@field send fun(job: integer, message: table): nil
---@field configure? fun(config: PackageInfoConfig): nil

---@class PackageInfoHelper
---@field source string
---@field runtime string
---@field state "idle" | "starting" | "installing" | "ready" | "failed"
---@field error? string
---@field failed_at? number
---@field job? integer
---@field next_id integer
---@field waiting PackageInfoEnsureCallback[]
---@field pending table<integer, {callback: PackageInfoReply, ticket: PackageInfoTicket}>
---@field ensure fun(callback: PackageInfoEnsureCallback): nil
---@field request fun(method: string, input: table, callback: PackageInfoReply, options?: {timeout?: integer}): PackageInfoTicket
---@field retry PackageInfoCancel
---@field cancel fun(ticket?: PackageInfoTicket): nil
---@field stop PackageInfoCancel
---@field configure fun(config: PackageInfoConfig): nil

---@class PackageInfoFastRegistry
---@field clients table<string, {client: string, job?: integer, time: number}>
---@field check fun(buf: integer, state: PackageInfoBuffer, force: boolean?, valid: PackageInfoValid, render: PackageInfoRender, fallback: PackageInfoCancel): nil
---@field clear PackageInfoCancel

---@class PackageInfoController
---@field renderer PackageInfoRenderQueue
---@field config PackageInfoConfig
---@field active boolean
---@field buffers table<integer, PackageInfoBuffer>
---@field cache table<string, PackageInfoCacheEntry>
---@field manager_failures table<string, {time: number, error: string}>
---@field manager_versions table<string, {major: integer, time: number}>
---@field setup fun(options?: PackageInfoOptions): nil
---@field teardown PackageInfoCancel
---@field refresh fun(buf?: integer, force?: boolean): nil
---@field invalidate fun(buf: integer, disabled?: boolean): nil
---@field toggle PackageInfoCancel
---@field info PackageInfoCancel
---@field status PackageInfoCancel

---@class PackageInfoAdapter
---@field schedule fun(delay: integer, callback: PackageInfoCancel): PackageInfoCancel
---@field namespace integer
---@field null? vim.NIL
---@field helper PackageInfoHelper
---@field queue PackageInfoQueue
---@field now fun(): number
---@field current fun(): {buf: integer, row: integer}
---@field buffer fun(buf: integer): PackageInfoHost?
---@field executable fun(name: string): boolean
---@field environment fun(): table<string, string>
---@field npm_path fun(): string
---@field user_config fun(): string?
---@field environment_hash fun(): string
---@field encode fun(value: table): string
---@field decode fun(text: string): unknown
---@field manifest fun(buf: integer): PackageInfoManifest?, string?
---@field notify fun(message: string): nil
---@field clear fun(buf: integer): nil
---@field render fun(buf: integer, rows: table<integer, PackageInfoChunk[]>): nil
---@field float fun(lines: string[], options?: PackageInfoFloat): nil
---@field configure? fun(config: PackageInfoConfig): nil
---@field install fun(controller: PackageInfoController): nil
---@field uninstall PackageInfoCancel
