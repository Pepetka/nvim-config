; extends
; Extra styled-components TypeScript patterns not covered by nvim-treesitter's
; bundled typescript/injections.scm.

; styled(Component)<{}>`<css>`
(call_expression
  function: (non_null_expression
    (instantiation_expression
      (call_expression
        function: (identifier) @_name
        (#eq? @_name "styled"))
      type_arguments: (type_arguments)))
  arguments: ((template_string) @injection.content
    (#offset! @injection.content 0 1 0 -1)
    (#set! injection.include-children)
    (#set! injection.language "styled")))

; styled(Component)<T>`<css>`
(binary_expression
  left: (binary_expression
    left: (call_expression
      function: (identifier) @_name
      (#eq? @_name "styled"))
    right: (identifier))
  right: (template_string) @injection.content
  (#offset! @injection.content 0 1 0 -1)
  (#set! injection.include-children)
  (#set! injection.language "styled"))
