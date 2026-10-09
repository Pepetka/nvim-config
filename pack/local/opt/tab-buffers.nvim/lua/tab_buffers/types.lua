---@class TabBuffersCore
---@field ensure_tab fun(self: TabBuffersCore, tab: integer): boolean
---@field tabs fun(self: TabBuffersCore): integer[]
---@field buffers fun(self: TabBuffersCore, tab: integer): integer[]
---@field contains fun(self: TabBuffersCore, tab: integer, buf: integer): boolean
---@field owners fun(self: TabBuffersCore, buf: integer): integer[]
---@field attach fun(self: TabBuffersCore, tab: integer, buf: integer, index?: integer): boolean
---@field detach fun(self: TabBuffersCore, tab: integer, buf: integer): boolean, boolean
---@field transfer fun(self: TabBuffersCore, from: integer, to: integer, buf: integer, index?: integer): boolean
---@field forget_buffer fun(self: TabBuffersCore, buf: integer): integer[]
---@field remove_tab fun(self: TabBuffersCore, tab: integer): TabBuffersRemovedTab
---@field move_to fun(self: TabBuffersCore, tab: integer, buf: integer, index: integer): boolean
---@field move fun(self: TabBuffersCore, tab: integer, buf: integer, offset: integer): boolean
---@field reorder fun(self: TabBuffersCore, tab: integer, buffers: integer[]): boolean
---@field sort fun(self: TabBuffersCore, tab: integer, less: fun(a: integer, b: integer): boolean): boolean
---@field neighbor fun(self: TabBuffersCore, tab: integer, buf: integer, offset: integer, wrap?: boolean): integer?
---@field replacement fun(self: TabBuffersCore, tab: integer, buf: integer): integer?
---@field targets fun(self: TabBuffersCore, tab: integer, mode: TabBuffersTargetMode, pivot?: integer): integer[]
---@field plan_close fun(self: TabBuffersCore, tab: integer, buffers: integer[]): TabBuffersClosePlan

---@alias TabBuffersTargetMode "one"|"all"|"others"|"left"|"right"

---@class TabBuffersClosePlan
---@field buffers integer[] Selected members, deduplicated and in tab order.
---@field shared integer[] Selected buffers that also belong to another tab.
---@field exclusive integer[] Selected buffers whose only owner is this tab.
---@field remaining integer[] Unselected buffers in tab order.

---@class TabBuffersRemovedTab
---@field buffers integer[] Previous buffers in tab order.
---@field orphans integer[] Buffers with no remaining owners, in previous tab order.

---@alias TabBuffersReplacement "right"|"left"|"last_used"
---@alias TabBuffersBufferFilter fun(buf: integer, facts: TabBuffersBufferFacts): boolean
---@alias TabBuffersTabFilter fun(tab: integer, facts: TabBuffersTabFacts): boolean

---@class TabBuffersSetupOptions
---@field close_empty_tab? boolean
---@field wrap? boolean
---@field replacement? TabBuffersReplacement
---@field bootstrap_hidden_buffers? boolean
---@field buffer_filter? TabBuffersBufferFilter
---@field tab_filter? TabBuffersTabFilter

---@class TabBuffersConfig
---@field close_empty_tab boolean
---@field wrap boolean
---@field replacement TabBuffersReplacement
---@field bootstrap_hidden_buffers boolean
---@field buffer_filter? TabBuffersBufferFilter
---@field tab_filter? TabBuffersTabFilter

---@class TabBuffersOptions
---@field tab? integer Stable tabpage handle, never a tab number.
---@field buf? integer
---@field win? integer
---@field index? integer
---@field force? boolean
---@field wrap? boolean
---@field split? "horizontal"|"vertical" Only used by open().

---@class TabBuffersResult
---@field closed integer[] Memberships successfully closed.
---@field failed {buf: integer, message: string}[]
---@field tab_closed boolean
---@field error? string

---@class TabBuffers
---@field setup fun(opts?: TabBuffersSetupOptions): boolean
---@field teardown fun(): boolean
---@field refresh fun(): boolean
---@field tabs fun(): integer[]
---@field buffers fun(tab?: integer): integer[]
---@field owners fun(buf?: integer): integer[]
---@field contains fun(buf?: integer, tab?: integer): boolean
---@field add fun(buf?: integer, opts?: TabBuffersOptions): boolean, string?
---@field transfer fun(target_tab: integer, opts?: TabBuffersOptions): boolean, string?
---@field move fun(offset: integer, opts?: TabBuffersOptions): boolean, string?
---@field move_to fun(index: integer, opts?: TabBuffersOptions): boolean, string?
---@field reorder fun(buffers: integer[], opts?: TabBuffersOptions): boolean, string?
---@field sort fun(by: ("id"|"name"|"path")|TabBuffersComparator, opts?: TabBuffersOptions): boolean, string?
---@field switch fun(offset: integer, opts?: TabBuffersOptions): integer?, string?
---@field next fun(opts?: TabBuffersOptions): integer?, string?
---@field previous fun(opts?: TabBuffersOptions): integer?, string?
---@field open fun(buf: integer, opts?: TabBuffersOptions): integer?, string?
---@field close fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_all fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_others fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_left fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_right fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_tab fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_many fun(buffers: integer[], opts?: TabBuffersOptions): TabBuffersResult

---@alias TabBuffersAction fun(): nil
---@alias TabBuffersComparator fun(a: integer, b: integer): boolean

---@class TabBuffersBufferFacts
---@field valid boolean
---@field listed boolean
---@field buftype string
---@field name string
---@field modified boolean
---@field loaded boolean
---@field has_text boolean

---@class TabBuffersTabFacts
---@field valid boolean
---@field excluded boolean

---@class TabBuffersWindowFacts
---@field valid boolean
---@field floating boolean
---@field external boolean
---@field preview boolean
---@field managed boolean

---@class TabBuffersContext
---@field tab integer
---@field win integer
---@field buf integer
---@field unmanaged boolean
---@field implicit_special boolean

---@class TabBuffersObservation
---@field buffers table<integer, TabBuffersBufferFacts>
---@field tabs table<integer, TabBuffersTabFacts>
---@field windows table<integer, TabBuffersWindowFacts>
---@field tab_windows table<integer, integer[]>
---@field displaying? table<integer, integer[]>

---@class TabBuffersCallbacks
---@field changed TabBuffersAction
---@field text? fun(buf: integer): nil
---@field buffer? fun(buf: integer): nil
---@field closing TabBuffersAction
---@field exiting TabBuffersAction

---@alias TabBuffersTransaction fun(): boolean?, string?
---@alias TabBuffersProtection fun(buffers: integer[], action: TabBuffersTransaction): boolean, boolean|string|nil, string?

---@class TabBuffersWindows
---@field protected TabBuffersProtection
---@field open fun(ctx: TabBuffersContext, buf: integer, opts: TabBuffersOptions): integer?, string?
---@field switch fun(ctx: TabBuffersContext, buf: integer): integer?, string?
---@field replace fun(tab: integer, buf: integer, replacement: integer?, scan: TabBuffersAction, commit: TabBuffersAction): boolean, string?
---@field guard_closing fun(buffers: integer[]): nil
---@field restore_closing TabBuffersAction

---@class TabBuffersAdapter: TabBuffersWindows
---@field current_tab fun(): integer
---@field current_buffer fun(): integer
---@field current_window fun(): integer
---@field tab_valid fun(tab: integer): boolean
---@field buffer_valid fun(buf: integer): boolean
---@field window_valid fun(win: integer): boolean
---@field tabs fun(): integer[]
---@field buffers fun(): integer[]
---@field tab_windows fun(tab: integer): integer[]
---@field window_buffer fun(win: integer): integer
---@field window_tab fun(win: integer): integer
---@field tab_window fun(tab: integer): integer
---@field buffer_name fun(buf: integer): string
---@field tab fun(tab: integer): TabBuffersTabFacts
---@field buffer fun(buf: integer): TabBuffersBufferFacts
---@field window fun(win: integer): TabBuffersWindowFacts
---@field displaying fun(buf: integer): integer[]
---@field delete_buffer fun(buf: integer, opts: { force: boolean }): nil
---@field focus_window fun(win: integer): nil
---@field schedule fun(action: TabBuffersAction): nil
---@field publish fun(tabs: integer[]): nil
---@field notify fun(message: string): nil
---@field exiting fun(): boolean
---@field install fun(callbacks: TabBuffersCallbacks): TabBuffersAction
---@field new_tab TabBuffersAction
---@field close_tab fun(tab: integer, force: boolean): nil
---@field new_working_window fun(tab?: integer): nil

---@class TabBuffersCloseRequest
---@field force boolean
---@field report TabBuffersResult

---@class TabBuffersRemoved
---@field tab integer
---@field buffers integer[]
---@field report TabBuffersResult
---@field own? TabBuffersCloseRequest

---@class TabBuffersOrphan
---@field force boolean
---@field error? string

---@class TabBuffersTextMetrics
---@field measure fun(text: string): integer
---@field length fun(text: string): integer
---@field suffix fun(text: string, first: integer): string Zero-based character offset, with combining marks kept.

---@alias TabBuffersHighlights table<string, vim.api.keyset.highlight>

---@class TabBuffersTablineOptions
---@field visibility? "auto"|"always"|"never"
---@field tab_width_ratio? number
---@field icons? boolean
---@field max_name_length? integer
---@field padding? integer
---@field offsets? string[]
---@field hide_filetypes? string[]
---@field highlights? TabBuffersHighlights|fun(): TabBuffersHighlights

---@class TabBuffersTablineConfig
---@field visibility "auto"|"always"|"never"
---@field tab_width_ratio number
---@field icons boolean
---@field max_name_length integer
---@field padding integer
---@field offsets string[]
---@field hide_filetypes string[]
---@field highlights TabBuffersHighlights|fun(): TabBuffersHighlights

---@class TabBuffersPanelEntry
---@field id integer
---@field name string
---@field modified boolean
---@field icon string

---@class TabBuffersLabelEntry
---@field id integer
---@field name string

---@class TabBuffersPanelSnapshot
---@field tab integer
---@field tabs integer[]
---@field active? integer
---@field visible table<integer, boolean>
---@field entries TabBuffersPanelEntry[]
---@field filetype string
---@field columns integer
---@field left integer
---@field right integer
---@field reviews table<integer, boolean>

---@class TabBuffersPanelItem
---@field kind "buffer"|"tab"
---@field id? integer
---@field tab integer
---@field active boolean
---@field highlight string
---@field text string

---@class TabBuffersPanelDocument
---@field text string
---@field targets table<integer, TabBuffersPanelItem>
---@field last_active table<integer, integer>
---@field visibility integer
---@field next_target integer

---@class TabBuffersPanelCallbacks
---@field changed TabBuffersAction
---@field theme TabBuffersAction
---@field metrics? TabBuffersAction

---@class TabBuffersPanelAdapter
---@field metrics TabBuffersTextMetrics
---@field schedule fun(action: TabBuffersAction): nil
---@field tab_valid fun(tab: integer): boolean
---@field buffer_valid fun(buf: integer): boolean
---@field focus_tab fun(tab: integer): nil
---@field notify fun(message: string): nil
---@field redraw TabBuffersAction
---@field highlights fun(input: TabBuffersHighlights|fun(): TabBuffersHighlights): TabBuffersHighlights
---@field apply fun(styles: TabBuffersHighlights?, shown: integer): nil
---@field snapshot fun(config: TabBuffersTablineConfig): TabBuffersPanelSnapshot
---@field install fun(callbacks: TabBuffersPanelCallbacks): TabBuffersAction

---@class TabBuffersTabline
---@field setup fun(opts?: TabBuffersTablineOptions): nil
---@field teardown fun(): boolean
---@field render fun(): string
---@field click fun(id: integer, clicks: integer, button: string, modifiers?: string): nil

---@class TabBuffersReviewFile
---@field absolute_path string

---@class TabBuffersReviewWindow
---@field id integer

---@class TabBuffersReviewLayout
---@field get_main_win fun(self: TabBuffersReviewLayout): TabBuffersReviewWindow

---@class TabBuffersReview
---@field tabpage? integer
---@field infer_cur_file? fun(self: TabBuffersReview): TabBuffersReviewFile?
---@field cur_entry? TabBuffersReviewFile
---@field cur_layout? TabBuffersReviewLayout

---@class TabBuffersReviewRecord
---@field view TabBuffersReview
---@field original unknown
---@field owned boolean

---@class TabBuffersReviews
---@field get fun(tab: integer): TabBuffersReview?
---@field observe fun(tab: integer, view: TabBuffersReview, original: unknown): boolean
---@field close fun(tab: integer, view: TabBuffersReview, current: unknown): boolean, unknown
---@field prune fun(valid: fun(tab: integer): boolean): nil

---@class TabBuffersDiffviewHooks: table<string, fun(...): nil>
---@field view_opened fun(view: TabBuffersReview): nil
---@field view_enter fun(view: TabBuffersReview): nil
---@field view_post_layout fun(view: TabBuffersReview): nil
---@field view_closed fun(view: TabBuffersReview): nil

---@class TabBuffersIcons
---@field get_icon fun(name: string, extension: string, opts: { default: boolean }): string?

---@class TabBuffersFzfOptions: table<string, unknown>
---@field no_hide? boolean
---@field no_resume? boolean
---@field prompt? string
---@field previewer? string|boolean
---@field file_icons? boolean
---@field color_icons? boolean
---@field fzf_opts? table<string, string|boolean|integer>
---@field actions? table<string, TabBuffersFzfAction|{ fn: TabBuffersFzfAction, reload: boolean }>

---@alias TabBuffersFzfAction fun(selected: string[]): nil
---@alias TabBuffersFzfWriter fun(line?: string): nil

---@class TabBuffersTextItem
---@field text string
---@field id? integer

---@class TabBuffersSidebar
---@field ordinary boolean
---@field filetype string
---@field column integer
---@field width integer
---@field height integer
