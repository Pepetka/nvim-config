---@alias DashboardAlign "left" | "center" | "right"
---@alias DashboardVerticalAlign "top" | "center" | "bottom"
---@alias DashboardMeasure fun(text: string): integer
---@alias DashboardKeyNormalizer fun(key: string): string
---@alias DashboardRun string | fun(context: DashboardContext): nil
---@alias DashboardStyles table<string, vim.api.keyset.highlight>
---@alias DashboardStyleProvider DashboardStyles | fun(): DashboardStyles
---@alias DashboardMapOpts fun(description: string, options?: vim.keymap.set.Opts): vim.keymap.set.Opts

---@class DashboardContext
---@field win integer
---@field source_buf integer
---@field width integer
---@field height integer

---@class DashboardItem
---@field id string
---@field label string
---@field icon? string
---@field key? string
---@field run DashboardRun

---@class DashboardSpan
---@field row integer Zero-based row.
---@field start_col integer Inclusive byte offset.
---@field end_col integer Exclusive byte offset.
---@field style string Semantic role, not a native highlight name.

---@class DashboardTarget
---@field id string Unique within its block.
---@field block_id? string Assigned by the layout composer.
---@field row integer Zero-based row.
---@field col integer Byte offset of the cursor.
---@field key? string
---@field run DashboardRun

---@class DashboardDocument
---@field lines string[]
---@field spans DashboardSpan[]
---@field targets DashboardTarget[]

---@class DashboardTextBlock
---@field enabled? boolean | fun(context: DashboardContext): boolean
---@field layout? DashboardBlockLayout
---@field id string
---@field type "text"
---@field lines string[] | fun(context: DashboardContext): string[]
---@field style? string Defaults to Text.

---@class DashboardActionsBlock
---@field enabled? boolean | fun(context: DashboardContext): boolean
---@field layout? DashboardBlockLayout
---@field id string
---@field type "actions"
---@field items DashboardItem[] | fun(context: DashboardContext): DashboardItem[]
---@field label_width? integer Minimum label width; omitted uses the widest label.
---@field spacing? integer Blank lines between actions; defaults to 1.

---@class DashboardCustomBlock
---@field enabled? boolean | fun(context: DashboardContext): boolean
---@field layout? DashboardBlockLayout
---@field id string
---@field type "custom"
---@field render fun(context: DashboardContext): DashboardDocument

---@alias DashboardBlock DashboardTextBlock | DashboardActionsBlock | DashboardCustomBlock

---@class DashboardBlockLayout
---@field align? DashboardAlign Inherits layout.horizontal.
---@field offset_x? integer Signed screen-cell shift, clamped at the left edge.
---@field gap_before? integer Additional blank lines before a nonempty block.
---@field gap_after? integer Additional blank lines after a nonempty block.

---@class DashboardNavigationKeys
---@field next string[]
---@field previous string[]
---@field activate string[]

---@class DashboardNavigationOptions
---@field keys? { next?: string[], previous?: string[], activate?: string[] }
---@field wrap? boolean Defaults to true.
---@field highlight_selected? boolean Defaults to false.

---@class DashboardNavigation
---@field keys DashboardNavigationKeys
---@field wrap boolean
---@field highlight_selected boolean

---@class DashboardChrome
---@field hide_statusline boolean
---@field hide_tabline boolean
---@field hide_winbar boolean

---@class DashboardComposeOptions
---@field block_layouts? DashboardBlockLayout[]
---@field navigation? DashboardNavigationKeys

---@class DashboardLayout
---@field horizontal DashboardAlign
---@field vertical DashboardVerticalAlign
---@field gap integer
---@field bottom_padding integer Space reserved below the document.

---@class DashboardOptions
---@field blocks? DashboardBlock[]
---@field layout? { horizontal?: DashboardAlign, vertical?: DashboardVerticalAlign, gap?: integer, bottom_padding?: integer }
---@field highlights? DashboardStyleProvider
---@field autostart? boolean
---@field hide_chrome? boolean
---@field chrome? { hide_statusline?: boolean, hide_tabline?: boolean, hide_winbar?: boolean }
---@field navigation? DashboardNavigationOptions
---@field map_opts? DashboardMapOpts Optional host keymap-options helper.

---@class DashboardConfig
---@field blocks DashboardBlock[]
---@field layout DashboardLayout
---@field highlights DashboardStyleProvider
---@field autostart boolean
---@field hide_chrome boolean
---@field chrome DashboardChrome
---@field navigation DashboardNavigation
---@field map_opts? DashboardMapOpts

---@class DashboardSession
---@field win integer
---@field buf integer
---@field source_buf integer
---@field document DashboardDocument
---@field selected? DashboardTarget

---@class DashboardCallbacks
---@field show fun(win?: integer): nil
---@field refresh fun(win?: integer): nil
---@field changed fun(): nil
---@field theme fun(): nil
---@field move fun(win: integer, delta: integer): nil
---@field activate fun(win: integer, block_id?: string, id?: string): nil

---@class DashboardAdapter
---@field context fun(win?: integer): DashboardContext
---@field measure DashboardMeasure
---@field normalize_key DashboardKeyNormalizer
---@field create fun(context: DashboardContext, track: fun(session: DashboardSession): nil): DashboardSession
---@field valid fun(session: DashboardSession): boolean
---@field apply fun(session: DashboardSession, document: DashboardDocument, selected?: DashboardTarget): nil
---@field select fun(session: DashboardSession, target?: DashboardTarget, document?: DashboardDocument): nil
---@field close fun(session: DashboardSession, restore: boolean): nil
---@field configure fun(config: DashboardConfig, styles: DashboardStyles): nil
---@field styles fun(styles: DashboardStyles): nil
---@field install fun(callbacks: DashboardCallbacks): nil
---@field uninstall fun(): nil
---@field reconcile fun(): nil
---@field aliases fun(): integer[] Windows displaying another session's buffer.
---@field schedule fun(callback: fun(): nil): nil
---@field run fun(action: DashboardRun, context: DashboardContext): nil
---@field notify fun(message: string): nil

---@class DashboardAPI
---@field setup fun(options?: DashboardOptions): nil
---@field show fun(win?: integer): nil
---@field hide fun(win?: integer): nil
---@field refresh fun(win?: integer): nil
---@field teardown fun(): nil

---@class DashboardController: DashboardAPI
---@field changed fun(): nil
---@field theme fun(): nil
---@field move fun(win: integer, delta: integer): nil
---@field activate fun(win: integer, block_id?: string, id?: string): nil
