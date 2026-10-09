---@alias CssInJsCancel fun(): nil
---@alias CssInJsEncoding "utf-8" | "utf-16" | "utf-32"
---@alias CssInJsReply fun(err: unknown, result: unknown): nil
---@alias CssInJsCompletionCallback fun(response: CssInJsResponse): nil

---@class CssInJsParserOverride
---@field setup fun(info: CssInJsParserInfo): nil
---@field teardown CssInJsCancel

---@alias CssInJsMethod "textDocument/completion" | "textDocument/hover"

---@class CssInJsParserInfo
---@field url string
---@field revision? string
---@field files? string[]
---@field location? string
---@field generate? boolean
---@field generate_from_json? boolean
---@field requires_generate_from_grammar? boolean
---@field cxx_standard? string

---@alias CssInJsHoverBorder "none" | "single" | "double" | "rounded" | "solid" | "shadow"

---@class CssInJsHoverOptions
---@field border? CssInJsHoverBorder
---@field max_width? integer
---@field max_height? integer

---@class CssInJsHoverConfig
---@field border CssInJsHoverBorder
---@field max_width? integer
---@field max_height? integer

---@class CssInJsConfig
---@field filter fun(buf: integer): boolean
---@field styled_parser? CssInJsParserInfo
---@field filetypes string[]
---@field server_name string
---@field request_timeout_ms integer
---@field poll_interval_ms integer
---@field trigger_characters string[]
---@field suppressed_lsp_clients string[]
---@field hover CssInJsHoverConfig

---@class CssInJsOptions
---@field filter? fun(buf: integer): boolean
---@field styled_parser? CssInJsParserInfo
---@field filetypes? string[]
---@field server_name? string
---@field request_timeout_ms? integer
---@field poll_interval_ms? integer
---@field trigger_characters? string[]
---@field suppressed_lsp_clients? string[]
---@field hover? CssInJsHoverOptions

---@class CssInJsRegion
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer
---@field substitutions CssInJsRegion[]

---@class CssInJsPublicRegion: CssInJsRegion
---@field node TSNode

---@class CssInJsSegment
---@field css_start integer
---@field css_end integer
---@field host_start integer
---@field host_end integer
---@field masked boolean

---@class CssInJsDocument
---@field lines string[]
---@field host_lines string[]
---@field host_start_row integer Zero-based row represented by host_lines[1].
---@field region CssInJsRegion
---@field maps CssInJsSegment[][]

---@class CssInJsContext
---@field bufnr integer
---@field cursor integer[] One-based row and zero-based byte column, like Blink.
---@field line string

---@class CssInJsItem: lsp.CompletionItem
---@field client_id? integer
---@field client_name? string
---@field cursor_column? integer

---@class CssInJsResponse
---@field items CssInJsItem[]
---@field is_incomplete_forward boolean
---@field is_incomplete_backward boolean

---@class CssInJsClient
---@field id integer
---@field name string
---@field initialized boolean
---@field stopped boolean
---@field encoding CssInJsEncoding
---@field completion boolean
---@field hover boolean

---@class CssInJsAllocation
---@field buf? integer
---@field client_id? integer

---@class CssInJsAdapter
---@field current fun(): CssInJsContext
---@field buffer fun(buf: integer): { filetype: string, buftype: string }?
---@field tick fun(buf: integer): integer?
---@field extract fun(buf: integer, row: integer, col: integer): CssInJsRegion?
---@field lines fun(buf: integer, first_row: integer, last_row: integer): string[] Zero-based, exclusive last row.
---@field client fun(id: integer): CssInJsClient?
---@field client_name fun(id: integer): string?
---@field create fun(host: integer): CssInJsAllocation, string?
---@field valid fun(allocation: CssInJsAllocation): boolean
---@field close fun(allocation: CssInJsAllocation): nil
---@field write fun(allocation: CssInJsAllocation, lines: string[]): nil
---@field uri fun(allocation: CssInJsAllocation): string
---@field request fun(
--- allocation: CssInJsAllocation,
--- method: CssInJsMethod,
--- params: lsp.CompletionParams | lsp.HoverParams,
--- callback: CssInJsReply,
---): integer?
---@field cancel fun(allocation: CssInJsAllocation, id: integer): nil
---@field now fun(): integer
---@field schedule fun(delay: integer, callback: CssInJsCancel): CssInJsCancel
---@field install fun(config: CssInJsConfig, deleted: fun(buf: integer): nil): nil
---@field uninstall CssInJsCancel
---@field fallback_hover CssInJsCancel
---@field show_hover fun(result: lsp.Hover?): nil
---@field notify fun(message: string): nil

---@class CssInJsJob
---@field done boolean
---@field deadline integer
---@field version integer
---@field tick integer
---@field timer? CssInJsCancel
---@field request_id? integer
---@field cancel CssInJsCancel

---@class CssInJsEntry
---@field allocation CssInJsAllocation
---@field document? CssInJsDocument
---@field filetype? string
---@field tick? integer
---@field version integer
---@field jobs table<CssInJsMethod, CssInJsJob>
---@field available boolean

---@class CssInJsController
---@field configuration fun(): CssInJsConfig
---@field setup fun(options?: CssInJsOptions): nil
---@field teardown CssInJsCancel
---@field deleted fun(buf: integer): nil
---@field supports_buffer fun(buf: integer): boolean
---@field context fun(buf: integer, row: integer, col: integer): CssInJsRegion?
---@field ready fun(buf: integer): boolean
---@field complete fun(ctx: CssInJsContext, callback: fun(response: CssInJsResponse): nil): CssInJsCancel?
---@field hover fun(): CssInJsCancel?

---@class CssInJsSource
---@field enabled fun(self: CssInJsSource): boolean
---@field get_trigger_characters fun(self: CssInJsSource): string[]
---@field get_completions fun(
--- self: CssInJsSource,
--- ctx: CssInJsContext,
--- callback: CssInJsCompletionCallback,
---): CssInJsCancel?
