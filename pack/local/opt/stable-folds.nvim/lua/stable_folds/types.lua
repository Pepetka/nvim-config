---@alias StableFoldsAction fun(): nil
---@alias StableFoldsBeforeChange fun(edit?: StableFoldsEdit): nil

---@class StableFoldsEdit
---@field start_row integer Zero-based.
---@field start_col integer Zero-based byte column.
---@field old_rows integer Row span relative to start_row.
---@field new_rows integer Row span relative to start_row.

---@class StableFoldsOptions
---@field filter? fun(buf: integer): boolean
---@field new_folds? "open"|"inherit" Defaults to "open"; "inherit" uses each window's foldlevel.
---@field include_injections? boolean Defaults to true.
---@field max_lines? integer Nonnegative; 0 disables the limit.
---@field max_bytes? integer Nonnegative; 0 disables the limit. UTF-8 bytes including line terminators.
---@field notify_errors? boolean Defaults to true; controls errors and configuration warnings.

---@class StableFoldsConfig
---@field filter fun(buf: integer): boolean
---@field new_folds "open"|"inherit"
---@field include_injections boolean
---@field max_lines integer
---@field max_bytes integer
---@field notify_errors boolean

---@class StableFoldsSize
---@field lines integer
---@field bytes integer

---@class StableFoldsRawRange
---@field start_row integer Zero-based.
---@field start_col integer Zero-based byte column.
---@field end_row integer Zero-based, exclusive end position.
---@field end_col integer Zero-based byte column.

---@class StableFoldsRange
---@field start integer One-based, inclusive.
---@field stop integer One-based, inclusive.

---@class StableFoldsContext
---@field buf integer
---@field win integer
---@field tick integer
---@field filetype string
---@field lang? string
---@field buftype string
---@field line integer
---@field minlines integer
---@field nestmax integer
---@field foldlevel integer

---@class StableFoldsSignature
---@field tick integer
---@field filetype string
---@field lang? string

---@class StableFoldsSnapshot: StableFoldsSignature
---@field line_count integer
---@field headers StableFoldsHeader[]
---@field ranges StableFoldsRange[]
---@field available boolean

---@class StableFoldsView
---@field buf integer
---@field snapshot StableFoldsSnapshot
---@field minlines integer
---@field nestmax integer
---@field levels string[]

---@class StableFoldsHeader
---@field line integer
---@field header string

---@class StableFoldsMark
---@field id integer
---@field header string
---@field new boolean

---@class StableFoldsPosition: StableFoldsMark
---@field line? integer Missing when the extmark no longer exists.
---@field level? integer Cached native fold depth for pre-read state inspection.
---@field old_line? integer Position before the byte edit.

---@class StableFoldsPlannedMark: StableFoldsHeader
---@field id? integer
---@field new boolean
---@field unchanged? boolean Existing extmark already occupies the requested row.

---@class StableFoldsApplied: StableFoldsSignature
---@field buf integer
---@field minlines integer
---@field nestmax integer
---@field view? StableFoldsView

---@class StableFoldsMarkPlan
---@field marks StableFoldsPlannedMark[]
---@field delete integer[]

---@class StableFoldsTracking: StableFoldsSignature
---@field marks StableFoldsMark[]
---@field positions? StableFoldsPosition[] Header positions retained while a buffer is unloaded.

---@class StableFoldsBuffer
---@field positions? StableFoldsPosition[] Invalidated by edits and reloads.
---@field positions_tick? integer
---@field snapshot? StableFoldsSnapshot
---@field pending_snapshot? StableFoldsSnapshot Translated levels until Tree-sitter edit callbacks complete.
---@field failure? StableFoldsSignature
---@field limited? StableFoldsSignature Rejected size cached until the buffer revision changes.
---@field tracking? StableFoldsTracking
---@field cancel? StableFoldsAction
---@field closed? table<integer, table<integer, boolean>> Window -> mark -> pre-edit closed state.
---@field reloading? boolean Disk read in progress; defer FileType reconciliation until on_reload.

---@class StableFoldsFoldState
---@field line integer
---@field closed boolean

---@class StableFoldsWatcher
---@field callback? StableFoldsBeforeChange
---@field reloaded? StableFoldsAction
---@field ready_tick? integer

---@class StableFoldsCallbacks
---@field changed fun(buf: integer): nil
---@field reading fun(buf: integer): nil
---@field unloaded fun(buf: integer): nil
---@field entered fun(buf: integer): nil
---@field reset fun(buf: integer): nil
---@field deleted fun(buf: integer): nil
---@field closed fun(win: integer): nil
---@field updated StableFoldsAction

---@class StableFoldsAdapter
---@field current_window fun(): integer
---@field line fun(): integer
---@field ready fun(buf: integer, tick: integer): boolean Whether the byte/reload notification has been delivered.
---@field settled fun(buf: integer): nil Mark a completed API edit as ready for an explicit refresh.
---@field context fun(win?: integer): StableFoldsContext?
---@field buffer fun(buf?: integer): integer?
---@field lines fun(buf: integer): string[]
---@field line_count fun(buf: integer): integer
---@field headers fun(buf: integer, ranges: StableFoldsRange[]): StableFoldsHeader[]
---@field size fun(buf: integer): StableFoldsSize
---@field collect fun(buf: integer, lang?: string, include_injections?: boolean): StableFoldsRawRange[]?
---@field positions fun(buf: integer, marks: StableFoldsMark[]): StableFoldsPosition[]
---@field apply_marks fun(buf: integer, plan: StableFoldsMarkPlan): StableFoldsMark[]
---@field clear fun(buf: integer): nil
---@field windows fun(buf: integer): integer[] Windows currently using this plugin's expression.
---@field buffers fun(): integer[] Buffers displayed in windows using this plugin's expression.
---@field attach fun(win?: integer): integer? Attached window, or nil if invalid.
---@field recompute fun(win: integer): nil
---@field open fun(win: integer, lines: integer[]): nil
---@field watch fun(buf: integer, before_change: StableFoldsBeforeChange, reloaded?: StableFoldsAction): StableFoldsAction
---@field closed fun(win: integer, positions: StableFoldsPosition[], adjust?: fun(shifted: boolean): nil): table<integer, boolean>
---@field restore fun(win: integer, states: StableFoldsFoldState[]): nil
---@field install fun(callbacks: StableFoldsCallbacks): nil
---@field uninstall StableFoldsAction
---@field notify fun(message: string): nil

---@class StableFoldsAPI
---@field foldexpr string
---@field setup fun(opts?: StableFoldsOptions): nil
---@field attach fun(win?: integer): nil
---@field expr fun(line?: integer): string
---@field refresh fun(buf?: integer): nil
---@field teardown StableFoldsAction

---@class StableFoldsController: StableFoldsAPI
