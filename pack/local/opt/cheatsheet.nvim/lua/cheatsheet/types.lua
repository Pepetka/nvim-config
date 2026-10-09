---@alias CheatsheetBorder "none" | "single" | "double" | "rounded" | "solid" | "shadow"
---@alias CheatsheetTitlePosition "left" | "center" | "right"
---@alias CheatsheetMode "n" | "i" | "v" | "o" | "t"
---@alias CheatsheetSortKey "alphanum" | "desc"
---@alias CheatsheetGroupAlign "left" | "center" | "right"
---@alias CheatsheetModeAlign "left" | "center" | "right"

---@class CheatsheetWindowPadding
---@field left integer
---@field right integer
---@field top integer
---@field bottom integer

---@class CheatsheetWindowConfig
---@field width number
---@field height number
---@field border CheatsheetBorder
---@field title string
---@field title_pos CheatsheetTitlePosition
---@field zindex integer
---@field padding CheatsheetWindowPadding

---@class CheatsheetGroupRule
---@field pattern string
---@field group string
---@field icon? string
---@field prefix? string Literal leading prefix; nil uses automatic removal, empty string preserves the description.

---@class CheatsheetDefaultGroup
---@field name string
---@field icon? string

---@class CheatsheetExcludeConfig
---@field no_desc boolean
---@field patterns string[]
---@field desc_patterns string[]
---@field single_word boolean
---@field newline boolean
---@field groups string[]

---@class CheatsheetIconsConfig
---@field enabled boolean
---@field default string

---@class CheatsheetMappingsConfig
---@field close string[]
---@field next_mode string
---@field prev_mode string

---@class CheatsheetLayoutConfig
---@field key_gap integer Spaces between the padded key column and the description.
---@field mapping_spacing integer Blank lines between mappings.
---@field group_spacing integer Blank lines between groups.

---@class CheatsheetConfig
---@field window CheatsheetWindowConfig
---@field modes CheatsheetMode[]
---@field group_rules CheatsheetGroupRule[]
---@field default_group CheatsheetDefaultGroup
---@field exclude CheatsheetExcludeConfig
---@field icons CheatsheetIconsConfig
---@field sort_groups string[]
---@field sort_keys CheatsheetSortKey
---@field group_align CheatsheetGroupAlign
---@field mode_align CheatsheetModeAlign
---@field group_underline boolean
---@field layout CheatsheetLayoutConfig
---@field mappings CheatsheetMappingsConfig
---@field open_mapping string | nil

---@class CheatsheetConfigPartial
---@field window? CheatsheetWindowConfigPartial
---@field modes? CheatsheetMode[]
---@field group_rules? CheatsheetGroupRule[]
---@field default_group? { name?: string, icon?: string }
---@field exclude? CheatsheetExcludeConfigPartial
---@field icons? { enabled?: boolean, default?: string }
---@field sort_groups? string[]
---@field sort_keys? CheatsheetSortKey
---@field group_align? CheatsheetGroupAlign
---@field mode_align? CheatsheetModeAlign
---@field group_underline? boolean
---@field layout? { key_gap?: integer, mapping_spacing?: integer, group_spacing?: integer }
---@field mappings? { close?: string[], next_mode?: string, prev_mode?: string }
---@field open_mapping? string | nil

---@class CheatsheetExcludeConfigPartial
---@field no_desc? boolean
---@field patterns? string[]
---@field desc_patterns? string[]
---@field single_word? boolean
---@field newline? boolean
---@field groups? string[]

---@class CheatsheetWindowConfigPartial
---@field width? number
---@field height? number
---@field border? CheatsheetBorder
---@field title? string
---@field title_pos? CheatsheetTitlePosition
---@field zindex? integer
---@field padding? { left?: integer, right?: integer, top?: integer, bottom?: integer }

---@class CheatsheetRawMapping
---@field lhs? string
---@field desc? string

---@class CheatsheetMappingContext
---@field mode CheatsheetMode
---@field leader string

---@class CheatsheetViewport
---@field columns integer
---@field lines integer

---@alias CheatsheetMeasure fun(text: string): integer
---@alias CheatsheetAction fun(): nil
---@alias CheatsheetResourceKind "win" | "buf"
---@alias CheatsheetLogLevel "WARN" | "ERROR"
---@alias CheatsheetHighlight
---| "CheatsheetTitle"
---| "CheatsheetGroup"
---| "CheatsheetGroupIcon"
---| "CheatsheetKey"
---| "CheatsheetDesc"
---| "CheatsheetSeparator"

---@class CheatsheetDisplayMapping
---@field lhs string
---@field desc string

---@class CheatsheetMapping: CheatsheetDisplayMapping
---@field mode CheatsheetMode

---@class CheatsheetDisplayGroup
---@field name string
---@field icon string
---@field mappings CheatsheetDisplayMapping[]

---@class CheatsheetGroup
---@field name string
---@field icon string
---@field mappings CheatsheetMapping[]

---@class CheatsheetGeometry
---@field width integer
---@field height integer
---@field row integer
---@field col integer

---@class CheatsheetSpan
---@field row integer Zero-based line index.
---@field start_col integer Zero-based byte offset, inclusive.
---@field end_col integer Zero-based byte offset, exclusive.
---@field hl_group CheatsheetHighlight

---@class CheatsheetDocument
---@field lines string[]
---@field spans CheatsheetSpan[]

---@class CheatsheetSession
---@field buf? integer
---@field win? integer
---@field source_buf integer
---@field source_win integer
---@field options CheatsheetConfig

---@class CheatsheetActions
---@field close CheatsheetAction
---@field next_mode CheatsheetAction
---@field prev_mode CheatsheetAction

---@class CheatsheetCallbacks
---@field toggle CheatsheetAction
---@field resize CheatsheetAction
---@field closed fun(kind: CheatsheetResourceKind, id: integer): nil

---@class CheatsheetAdapter
---@field source fun(): integer, integer
---@field viewport fun(): CheatsheetViewport
---@field leader fun(): string
---@field measure CheatsheetMeasure
---@field collect fun(mode: CheatsheetMode, source_buf: integer): CheatsheetRawMapping[], CheatsheetRawMapping[]
---@field valid fun(session: CheatsheetSession): boolean
---@field exists fun(session: CheatsheetSession): boolean
---@field create fun(
---  options: CheatsheetConfig,
---  source_buf: integer,
---  source_win: integer,
---  actions: CheatsheetActions,
---  size: CheatsheetGeometry,
---): CheatsheetSession, string?
---@field update fun(
---  session: CheatsheetSession,
---  size: CheatsheetGeometry,
---  document: CheatsheetDocument,
---  reset: boolean,
---): nil
---@field close fun(session: CheatsheetSession): nil
---@field install fun(config: CheatsheetConfig, callbacks: CheatsheetCallbacks): nil
---@field displayed fun(value: boolean): nil
---@field notify fun(message: string, level: CheatsheetLogLevel): nil

---@class CheatsheetAPI
---@field setup fun(opts?: CheatsheetConfigPartial): nil
---@field show fun(mode?: CheatsheetMode): nil
---@field hide CheatsheetAction
---@field toggle CheatsheetAction
---@field next_mode CheatsheetAction
---@field prev_mode CheatsheetAction

---@class CheatsheetController: CheatsheetAPI
---@field resize CheatsheetAction
---@field closed fun(kind: CheatsheetResourceKind, id: integer): nil
