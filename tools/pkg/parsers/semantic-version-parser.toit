import encoding.yaml.parser

class SemanticVersionParseResult:
  triple/TripleParseResult
  pre-releases/List
  build-numbers/List
  offset/int

  constructor .triple .pre-releases .build-numbers .offset:

class TripleParseResult:
  triple/List
  constructor major/int minor/int patch/int:
    triple = [major, minor, patch]

/*
  A PEG grammar for the semantic version
  semantic-version ::= version-core
                       pre-releases?
                       build-numbers?
  version-core ::= numeric '.' numeric '.' numeric
  pre-releases ::= '-' pre-release ('.' pre-release)*
  build-numbers ::= '+' build-number ('.' build-number)*

  pre-release ::= alphanumeric | numeric
  build-number ::= alphanumeric | digit+

  alphanumeric ::= digit* non-digit identifier-char*

  identifier-char ::= digit | non-digit

  non-digit ::= '-' | letter
  numeric ::= '0' | (digit - '0') digit *
  digit ::= [0-9]
  letter := [a-zA-Z]
*/

class SemanticVersionParser extends parser.PegParserBase_:
  constructor source/string:
    super source.to-byte-array

  expect-match_ char/int -> int:
    if matched := match-char char: return matched
    throw "Parse error, expected $(string.from-rune char) at position $current-position"

  expect-numeric -> int:
    if number := numeric: return number
    throw "Parse error, expected a numeric value at position $current-position"

  semantic-version --consume-all/bool=false -> SemanticVersionParseResult:
    triple := version-core
    pre-releases := pre-releases
    build-numbers := build-numbers

    if consume-all and not eof: throw "Parse error, not all input was consumed"

    return SemanticVersionParseResult triple pre-releases build-numbers current-position

  version-core -> TripleParseResult:
    major := expect-numeric
    expect-match_ '.'
    minor := expect-numeric
    expect-match_ '.'
    patch := expect-numeric
    return TripleParseResult major minor patch

  pre-releases -> List:
    with-rollback:
      result := []
      if match-char '-':
        while true:
          if pre-release-result := pre-release: result.add pre-release-result
          else: break
          if not match-char '.': return result
    return []

  build-numbers -> List:
    with-rollback:
      result := []
      if match-char '+':
        while true:
          result.add build-number
          if not match-char '.': return result
    return []

  pre-release -> any:
    if alphanumeric-result := alphanumeric: return alphanumeric-result
    if numeric-result := numeric: return numeric-result
    throw "Parse error in pre-release, expected an identifier or a number at position $current-position"

  build-number -> string:
    if alphanumeric-result := alphanumeric: return alphanumeric-result
    with-rollback:
      mark := mark
      if (repeat --at-least-one: digit):
        return string-since mark
    throw "Parse error in build-number, expected an identifier or digits at position $current-position"

  alphanumeric -> string?:
    mark := mark
    with-rollback:
      if (repeat: digit) and
         non-digit and
         (repeat: identifier-char):
        return string-since mark
    return null

  identifier-char -> bool:
    return digit or non-digit

  non-digit -> bool:
    if match-char '-' or letter: return true
    return false

  numeric -> int?:
    if match-char '0': return 0
    mark := mark
    with-rollback:
      if digit and (repeat: digit):
        return int.parse (string-since mark)
    return null

  digit -> bool:
    return (match-range '0' '9') != null

  letter -> bool:
    return (match-range 'a' 'z') != null or
           (match-range 'A' 'Z') != null