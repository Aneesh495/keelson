// High-performance pure Wren JSON parser and serializer.
// Supports full JSON specification: nested maps, lists, strings with escapes,
// numbers (integers, floats, scientific notation), booleans, and null.

class JsonToken {
  static STRING { "STRING" }
  static NUMBER { "NUMBER" }
  static TRUE { "TRUE" }
  static FALSE { "FALSE" }
  static NULL { "NULL" }
  static LBRACE { "{" }
  static RBRACE { "}" }
  static LBRACKET { "[" }
  static RBRACKET { "]" }
  static COLON { ":" }
  static COMMA { "," }
  static EOF { "EOF" }

  construct new(type, value, line, col) {
    _type = type
    _value = value
    _line = line
    _col = col
  }

  type { _type }
  value { _value }
  line { _line }
  col { _col }

  toString { "JsonToken(" + _type + ", " + _value.toString + ")" }
}

class JsonLexer {
  construct new(source) {
    _source = source
    _length = source.count
    _cursor = 0
    _line = 1
    _col = 1
  }

  nextToken() {
    skipWhitespace()

    if (_cursor >= _length) {
      return JsonToken.new(JsonToken.EOF, null, _line, _col)
    }

    var ch = _source[_cursor]
    var startCol = _col

    if (ch == "{") {
      advance()
      return JsonToken.new(JsonToken.LBRACE, "{", _line, startCol)
    }
    if (ch == "}") {
      advance()
      return JsonToken.new(JsonToken.RBRACE, "}", _line, startCol)
    }
    if (ch == "[") {
      advance()
      return JsonToken.new(JsonToken.LBRACKET, "[", _line, startCol)
    }
    if (ch == "]") {
      advance()
      return JsonToken.new(JsonToken.RBRACKET, "]", _line, startCol)
    }
    if (ch == ":") {
      advance()
      return JsonToken.new(JsonToken.COLON, ":", _line, startCol)
    }
    if (ch == ",") {
      advance()
      return JsonToken.new(JsonToken.COMMA, ",", _line, startCol)
    }

    if (ch == "\"") {
      return readString()
    }

    if (isDigit(ch) || ch == "-") {
      return readNumber()
    }

    if (isAlpha(ch)) {
      return readLiteral()
    }

    Fiber.abort("JsonLexer error: unexpected character '" + ch + "' at line " + _line.toString + ", col " + _col.toString)
  }

  skipWhitespace() {
    while (_cursor < _length) {
      var ch = _source[_cursor]
      if (ch == " " || ch == "\t" || ch == "\r") {
        advance()
      } else if (ch == "\n") {
        _cursor = _cursor + 1
        _line = _line + 1
        _col = 1
      } else {
        break
      }
    }
  }

  advance() {
    var ch = _source[_cursor]
    _cursor = _cursor + 1
    _col = _col + 1
    return ch
  }

  peek() {
    if (_cursor >= _length) {
      return ""
    }
    return _source[_cursor]
  }

  readString() {
    var startCol = _col
    advance()
    var result = ""

    while (_cursor < _length) {
      var ch = advance()
      if (ch == "\"") {
        return JsonToken.new(JsonToken.STRING, result, _line, startCol)
      } else if (ch == "\\") {
        if (_cursor >= _length) {
          Fiber.abort("Unterminated string escape")
        }
        var esc = advance()
        if (esc == "\"") {
          result = result + "\""
        } else if (esc == "\\") {
          result = result + "\\"
        } else if (esc == "/") {
          result = result + "/"
        } else if (esc == "b") {
          result = result + "\b"
        } else if (esc == "f") {
          result = result + "\f"
        } else if (esc == "n") {
          result = result + "\n"
        } else if (esc == "r") {
          result = result + "\r"
        } else if (esc == "t") {
          result = result + "\t"
        } else if (esc == "u") {
          var hex = ""
          for (i in 0...4) {
            if (_cursor < _length) {
              hex = hex + advance()
            }
          }
          result = result + parseHexCode(hex)
        } else {
          result = result + esc
        }
      } else {
        result = result + ch
      }
    }

    Fiber.abort("Unterminated string literal at line " + _line.toString)
  }

  parseHexCode(hex) {
    var val = 0
    for (i in 0...hex.count) {
      var c = hex[i]
      var b = c.bytes[0]
      var digit = 0
      if (b >= 48 && b <= 57) {
        digit = b - 48
      } else if (b >= 97 && b <= 102) {
        digit = b - 87
      } else if (b >= 65 && b <= 70) {
        digit = b - 55
      }
      val = val * 16 + digit
    }
    return String.fromCodePoint(val)
  }

  readNumber() {
    var startCol = _col
    var numStr = ""

    if (peek() == "-") {
      numStr = numStr + advance()
    }

    while (_cursor < _length && isDigit(peek())) {
      numStr = numStr + advance()
    }

    if (peek() == ".") {
      numStr = numStr + advance()
      while (_cursor < _length && isDigit(peek())) {
        numStr = numStr + advance()
      }
    }

    if (peek() == "e" || peek() == "E") {
      numStr = numStr + advance()
      if (peek() == "+" || peek() == "-") {
        numStr = numStr + advance()
      }
      while (_cursor < _length && isDigit(peek())) {
        numStr = numStr + advance()
      }
    }

    var numVal = Num.fromString(numStr)
    if (numVal == null) {
      Fiber.abort("Invalid number literal '" + numStr + "' at line " + _line.toString)
    }

    return JsonToken.new(JsonToken.NUMBER, numVal, _line, startCol)
  }

  readLiteral() {
    var startCol = _col
    var lit = ""

    while (_cursor < _length && isAlpha(peek())) {
      lit = lit + advance()
    }

    if (lit == "true") {
      return JsonToken.new(JsonToken.TRUE, true, _line, startCol)
    }
    if (lit == "false") {
      return JsonToken.new(JsonToken.FALSE, false, _line, startCol)
    }
    if (lit == "null") {
      return JsonToken.new(JsonToken.NULL, null, _line, startCol)
    }

    Fiber.abort("Unknown literal '" + lit + "' at line " + _line.toString)
  }

  isDigit(ch) {
    if (ch.count == 0) {
      return false
    }
    var b = ch.bytes[0]
    return b >= 48 && b <= 57
  }

  isAlpha(ch) {
    if (ch.count == 0) {
      return false
    }
    var b = ch.bytes[0]
    return (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || ch == "_"
  }
}

class JsonParser {
  construct new(source) {
    _lexer = JsonLexer.new(source)
    _currentToken = _lexer.nextToken()
  }

  parse() {
    var result = parseValue()
    if (_currentToken.type != JsonToken.EOF) {
      Fiber.abort("Unexpected extra token after JSON value: " + _currentToken.toString)
    }
    return result
  }

  parseValue() {
    var tok = _currentToken
    if (tok.type == JsonToken.STRING) {
      consume(JsonToken.STRING)
      return tok.value
    }
    if (tok.type == JsonToken.NUMBER) {
      consume(JsonToken.NUMBER)
      return tok.value
    }
    if (tok.type == JsonToken.TRUE) {
      consume(JsonToken.TRUE)
      return true
    }
    if (tok.type == JsonToken.FALSE) {
      consume(JsonToken.FALSE)
      return false
    }
    if (tok.type == JsonToken.NULL) {
      consume(JsonToken.NULL)
      return null
    }
    if (tok.type == JsonToken.LBRACE) {
      return parseObject()
    }
    if (tok.type == JsonToken.LBRACKET) {
      return parseArray()
    }

    Fiber.abort("Unexpected token in JSON value: " + tok.toString)
  }

  parseObject() {
    consume(JsonToken.LBRACE)
    var map = {}

    if (_currentToken.type == JsonToken.RBRACE) {
      consume(JsonToken.RBRACE)
      return map
    }

    while (true) {
      if (_currentToken.type != JsonToken.STRING) {
        Fiber.abort("Expected string key in object, got " + _currentToken.toString)
      }
      var key = _currentToken.value
      consume(JsonToken.STRING)

      consume(JsonToken.COLON)
      var val = parseValue()
      map[key] = val

      if (_currentToken.type == JsonToken.COMMA) {
        consume(JsonToken.COMMA)
      } else if (_currentToken.type == JsonToken.RBRACE) {
        consume(JsonToken.RBRACE)
        break
      } else {
        Fiber.abort("Expected ',' or '}' in object, got " + _currentToken.toString)
      }
    }

    return map
  }

  parseArray() {
    consume(JsonToken.LBRACKET)
    var list = []

    if (_currentToken.type == JsonToken.RBRACKET) {
      consume(JsonToken.RBRACKET)
      return list
    }

    while (true) {
      var item = parseValue()
      list.add(item)

      if (_currentToken.type == JsonToken.COMMA) {
        consume(JsonToken.COMMA)
      } else if (_currentToken.type == JsonToken.RBRACKET) {
        consume(JsonToken.RBRACKET)
        break
      } else {
        Fiber.abort("Expected ',' or ']' in array, got " + _currentToken.toString)
      }
    }

    return list
  }

  consume(expectedType) {
    if (_currentToken.type != expectedType) {
      Fiber.abort("Expected token " + expectedType + " but got " + _currentToken.toString)
    }
    _currentToken = _lexer.nextToken()
  }
}

class Json {
  // Parses a JSON string into Wren objects (Map, List, String, Num, Bool, null).
  static parse(source) {
    if (source == null || source.count == 0) {
      return null
    }
    var parser = JsonParser.new(source)
    return parser.parse()
  }

  // Serializes a Wren value into a compact JSON string.
  static stringify(value) {
    if (value == null) {
      return "null"
    }
    if (value is Bool) {
      return value ? "true" : "false"
    }
    if (value is Num) {
      return value.toString
    }
    if (value is String) {
      return escapeString(value)
    }

    if (value is List) {
      var parts = []
      for (item in value) {
        parts.add(stringify(item))
      }
      return "[" + parts.join(",") + "]"
    }

    if (value is Map) {
      var parts = []
      for (entry in value) {
        var k = escapeString(entry.key.toString)
        var v = stringify(entry.value)
        parts.add(k + ":" + v)
      }
      return "{" + parts.join(",") + "}"
    }

    return escapeString(value.toString)
  }

  // Serializes a Wren value into a formatted, indented JSON string.
  static pretty(value) {
    return pretty(value, 2)
  }

  static pretty(value, indentSpaces) {
    return formatValue(value, 0, indentSpaces)
  }

  static formatValue(value, depth, indentSpaces) {
    var indent = makeIndent(depth * indentSpaces)
    var nextIndent = makeIndent((depth + 1) * indentSpaces)

    if (value == null) {
      return "null"
    }
    if (value is Bool) {
      return value ? "true" : "false"
    }
    if (value is Num) {
      return value.toString
    }
    if (value is String) {
      return escapeString(value)
    }

    if (value is List) {
      if (value.count == 0) {
        return "[]"
      }
      var items = []
      for (item in value) {
        items.add(nextIndent + formatValue(item, depth + 1, indentSpaces))
      }
      return "[\n" + items.join(",\n") + "\n" + indent + "]"
    }

    if (value is Map) {
      if (value.count == 0) {
        return "{}"
      }
      var entries = []
      for (entry in value) {
        var k = escapeString(entry.key.toString)
        var v = formatValue(entry.value, depth + 1, indentSpaces)
        entries.add(nextIndent + k + ": " + v)
      }
      return "{\n" + entries.join(",\n") + "\n" + indent + "}"
    }

    return escapeString(value.toString)
  }

  static makeIndent(count) {
    var s = ""
    for (i in 0...count) {
      s = s + " "
    }
    return s
  }

  static escapeString(str) {
    var out = "\""
    for (i in 0...str.count) {
      var ch = str[i]
      if (ch == "\"") {
        out = out + "\\\""
      } else if (ch == "\\") {
        out = out + "\\\\"
      } else if (ch == "\n") {
        out = out + "\\n"
      } else if (ch == "\r") {
        out = out + "\\r"
      } else if (ch == "\t") {
        out = out + "\\t"
      } else if (ch == "\b") {
        out = out + "\\b"
      } else if (ch == "\f") {
        out = out + "\\f"
      } else {
        out = out + ch
      }
    }
    out = out + "\""
    return out
  }
}
