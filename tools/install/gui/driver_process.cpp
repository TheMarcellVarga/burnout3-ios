#include "driver_process.h"

#include <QCoreApplication>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#ifdef Q_OS_UNIX
#include <signal.h>
#include <sys/types.h>
#include <unistd.h>
#endif

#ifdef Q_OS_WIN
// A child of this window program never gets a console window of its own,
// whatever subsystem its executable has (taskkill, a Python driver).
static void NoConsole(QProcess* process) {
  process->setCreateProcessArgumentsModifier(
      [](QProcess::CreateProcessArguments* args) { args->flags |= CREATE_NO_WINDOW; });
}
#endif

DriverProcess::DriverProcess(QObject* parent) : QObject(parent) {
  qRegisterMetaType<DriverProcess::Result>();
  kill_timer_.setSingleShot(true);
  kill_timer_.setInterval(4000);
  connect(&kill_timer_, &QTimer::timeout, this, [this] {
    if (IsRunning()) {
#ifdef Q_OS_UNIX
      KillGroup(SIGKILL);
#endif
      process_->kill();
    }
  });
}

DriverProcess::~DriverProcess() {
  blockSignals(true);  // nobody is listening any more: the window may be half destroyed
  if (IsRunning()) {
    result_.cancelled = true;
#ifdef Q_OS_UNIX
    KillGroup(SIGKILL);
#endif
    process_->kill();
    process_->waitForFinished(2000);
  }
}

void DriverProcess::Start(const QString& program, const QStringList& arguments,
                          const QProcessEnvironment& env, const QString& working_directory) {
  process_ = new QProcess(this);
#ifdef Q_OS_WIN
  NoConsole(process_);
#endif
  process_->setProcessEnvironment(env);
  if (!working_directory.isEmpty()) {
    process_->setWorkingDirectory(working_directory);
  }
#ifdef Q_OS_UNIX
  // A session of its own: the process id is then also the process group id.
  process_->setChildProcessModifier([] { ::setsid(); });
#endif
  connect(process_, &QProcess::readyReadStandardOutput, this, &DriverProcess::ReadStdout);
  connect(process_, &QProcess::readyReadStandardError, this, &DriverProcess::ReadStderr);
  connect(process_, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
    if (error == QProcess::FailedToStart && !reported_) {
      reported_ = true;
      result_.started = false;
      result_.start_error = process_->errorString();
      emit Finished(result_);
    }
  });
  connect(process_, &QProcess::finished, this,
          [this](int code, QProcess::ExitStatus status) {
            kill_timer_.stop();
            ReadStdout();
            ReadStderr();
            // A last line without a newline.
            for (QByteArray* buffer : {&out_buffer_, &err_buffer_}) {
              if (!buffer->trimmed().isEmpty()) {
                buffer->append('\n');
              }
            }
            ReadStdout();
            ReadStderr();
            if (reported_) {
              return;
            }
            reported_ = true;
            result_.exit_code = code;
            result_.crashed = status != QProcess::NormalExit;
            emit Finished(result_);
          });
  process_->start(program, arguments);
}

void DriverProcess::Cancel() {
  if (!IsRunning()) {
    return;
  }
  result_.cancelled = true;
#ifdef Q_OS_UNIX
  KillGroup(SIGTERM);
#else
  // taskkill /T takes the children with it.
  auto* killer = new QProcess(this);
  NoConsole(killer);
  connect(killer, &QProcess::finished, killer, &QObject::deleteLater);
  connect(killer, &QProcess::errorOccurred, killer, &QObject::deleteLater);
  killer->start("taskkill", {"/PID", QString::number(process_->processId()), "/T", "/F"});
#endif
  kill_timer_.start();
}

void DriverProcess::KillGroup(int signal_number) {
#ifdef Q_OS_UNIX
  const qint64 pid = process_ ? process_->processId() : 0;
  if (pid > 1) {
    ::kill(-static_cast<pid_t>(pid), signal_number);
  }
#else
  Q_UNUSED(signal_number);
#endif
}

void DriverProcess::ReadStdout() {
  if (!process_) {
    return;
  }
  out_buffer_ += process_->readAllStandardOutput();
  int newline;
  while ((newline = out_buffer_.indexOf('\n')) >= 0) {
    const QString line = QString::fromUtf8(out_buffer_.left(newline)).trimmed();
    out_buffer_.remove(0, newline + 1);
    if (line.isEmpty()) {
      continue;
    }
    emit RawLine(line);
    const Event event = ParseLine(line);
    if (event.kind != Event::Kind::Unknown) {
      result_.saw_protocol = true;
    }
    if (event.kind == Event::Kind::ResultOk || event.kind == Event::Kind::ResultFail) {
      result_.saw_result = true;
    }
    emit EventReceived(event);
  }
}

void DriverProcess::ReadStderr() {
  if (!process_) {
    return;
  }
  err_buffer_ += process_->readAllStandardError();
  int newline;
  while ((newline = err_buffer_.indexOf('\n')) >= 0) {
    const QString line = QString::fromUtf8(err_buffer_.left(newline)).trimmed();
    err_buffer_.remove(0, newline + 1);
    if (!line.isEmpty()) {
      result_.stderr_tail.append(line);
      while (result_.stderr_tail.size() > 40) {
        result_.stderr_tail.removeFirst();
      }
    }
  }
}
