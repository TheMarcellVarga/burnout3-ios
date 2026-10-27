#pragma once

#include <QString>
#include <QStringList>

// One line of what the game's installer prints on stdout (docs/installer.md,
// "Protocol"). The window only reads these; it makes no decisions the installer owns.
struct Event {
  enum class Kind {
    Unknown,     // not a protocol line; kept as text
    Protocol,    // PROTOCOL <version>
    Plan,        // PLAN <step>...           -> steps
    Begin,       // STEP <step> BEGIN <text>
    Progress,    // PROGRESS <step> <0..1> <text>
    Log,         // LOG <step> <text>
    Warn,        // WARN <step> <text>
    Missing,     // MISSING <step> <what> <hint>
    Skip,        // STEP <step> SKIP <text>
    Ok,          // STEP <step> OK <text>
    Fail,        // STEP <step> FAIL <code> <text>
    ResultOk,    // RESULT OK <path>          -> text
    ResultFail,  // RESULT FAIL <step> <code>
  };
  Kind kind = Kind::Unknown;
  QString step;
  QString text;   // description, summary, message, path, ...
  QString code;   // failure code
  QString what;   // MISSING: the item
  QString hint;   // MISSING: how to get it
  double fraction = 0.0;
  QStringList steps;  // PLAN
  int version = 0;    // PROTOCOL
};

Event ParseLine(const QString& line);
