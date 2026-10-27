#include "protocol.h"

namespace {

// Takes the first space-separated word off `s` (and the spaces after it).
QString TakeWord(QString* s) {
  const int space = s->indexOf(' ');
  QString word;
  if (space < 0) {
    word = *s;
    s->clear();
  } else {
    word = s->left(space);
    *s = s->mid(space + 1);
    while (s->startsWith(' ')) {
      s->remove(0, 1);
    }
  }
  return word;
}

}  // namespace

Event ParseLine(const QString& raw) {
  Event e;
  QString rest = raw.trimmed();
  e.text = rest;
  const QString word = TakeWord(&rest);
  using K = Event::Kind;
  if (word == "PROTOCOL") {
    e.kind = K::Protocol;
    e.version = rest.toInt();
  } else if (word == "PLAN") {
    e.kind = K::Plan;
    e.steps = rest.split(' ', Qt::SkipEmptyParts);
  } else if (word == "STEP") {
    e.step = TakeWord(&rest);
    const QString what = TakeWord(&rest);
    if (e.step.isEmpty()) {
      return e;
    }
    if (what == "BEGIN") {
      e.kind = K::Begin;
      e.text = rest;
    } else if (what == "SKIP") {
      e.kind = K::Skip;
      e.text = rest;
    } else if (what == "OK") {
      e.kind = K::Ok;
      e.text = rest;
    } else if (what == "FAIL") {
      e.kind = K::Fail;
      e.code = TakeWord(&rest);
      e.text = rest;
    } else {
      e.kind = K::Unknown;
      e.text = raw.trimmed();
    }
  } else if (word == "PROGRESS") {
    e.kind = K::Progress;
    e.step = TakeWord(&rest);
    bool ok = false;
    e.fraction = TakeWord(&rest).toDouble(&ok);
    if (!ok) {
      e.kind = K::Unknown;
      e.text = raw.trimmed();
      return e;
    }
    e.text = rest;
  } else if (word == "LOG" || word == "WARN") {
    e.kind = word == "LOG" ? K::Log : K::Warn;
    e.step = TakeWord(&rest);
    e.text = rest;
  } else if (word == "MISSING") {
    e.kind = K::Missing;
    e.step = TakeWord(&rest);
    e.what = TakeWord(&rest);
    e.hint = rest;
    e.text = e.what;
  } else if (word == "RESULT") {
    const QString what = TakeWord(&rest);
    if (what == "OK") {
      e.kind = K::ResultOk;
      e.text = rest;
    } else if (what == "FAIL") {
      e.kind = K::ResultFail;
      e.step = TakeWord(&rest);
      e.code = TakeWord(&rest);
      e.text = e.code;
    }
  }
  return e;
}
