// Cron expression parser and next-occurrence calculator for recurring workflows.
// Supports standard 5-field expressions (minute, hour, day-of-month, month, day-of-week),
// wildcards (*), steps (*/n), ranges (a-b), and lists (a,b,c).

class CronField {
  construct new(minVal, maxVal) {
    _minVal = minVal
    _maxVal = maxVal
    _allowed = {}
  }

  isAllowed(val) {
    return _allowed.containsKey(val)
  }

  parse(fieldStr) {
    _allowed.clear()

    if (fieldStr == "*") {
      for (i in _minVal.._maxVal) {
        _allowed[i] = true
      }
      return
    }

    var commaParts = fieldStr.split(",")
    for (part in commaParts) {
      if (part.contains("/")) {
        var slashParts = part.split("/")
        var baseStr = slashParts[0]
        var step = Num.fromString(slashParts[1])
        if (step == null || step <= 0) step = 1

        var start = _minVal
        var finish = _maxVal
        if (baseStr != "*") {
          start = Num.fromString(baseStr)
          if (start == null) start = _minVal
        }

        var i = start
        while (i <= finish) {
          _allowed[i] = true
          i = i + step
        }
      } else if (part.contains("-")) {
        var dashParts = part.split("-")
        var start = Num.fromString(dashParts[0])
        var finish = Num.fromString(dashParts[1])
        if (start != null && finish != null) {
          for (i in start..finish) {
            _allowed[i] = true
          }
        }
      } else {
        var single = Num.fromString(part)
        if (single != null) {
          _allowed[single] = true
        }
      }
    }
  }
}

class CronExpression {
  construct new(expression) {
    _expression = expression
    _minute = CronField.new(0, 59)
    _hour = CronField.new(0, 23)
    _dayOfMonth = CronField.new(1, 31)
    _month = CronField.new(1, 12)
    _dayOfWeek = CronField.new(0, 6) // 0 = Sunday

    parse(expression)
  }

  expression { _expression }

  parse(expr) {
    var parts = expr.split(" ")
    if (parts.count < 5) {
      Fiber.abort("Invalid cron expression: expected 5 fields, got " + parts.count.toString)
    }

    _minute.parse(parts[0])
    _hour.parse(parts[1])
    _dayOfMonth.parse(parts[2])
    _month.parse(parts[3])
    _dayOfWeek.parse(parts[4])
  }

  // Tests whether the given date/time components match this cron schedule.
  matches(minute, hour, dayOfMonth, month, dayOfWeek) {
    return _minute.isAllowed(minute) &&
           _hour.isAllowed(hour) &&
           _dayOfMonth.isAllowed(dayOfMonth) &&
           _month.isAllowed(month) &&
           _dayOfWeek.isAllowed(dayOfWeek)
  }
}
