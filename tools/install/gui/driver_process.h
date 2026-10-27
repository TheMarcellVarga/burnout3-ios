#pragma once

#include <QObject>
#include <QProcess>
#include <QProcessEnvironment>
#include <QStringList>
#include <QTimer>

#include "protocol.h"

// Runs the game's executable with one of its installer command lines
// (--data-status, --install, --build-shaders) and turns its stdout into Events.
// One run per object. It is started in its own process group (session on Unix) so
// Cancel can stop it together with what it started (the shader build starts the
// game once per scene).
class DriverProcess : public QObject {
  Q_OBJECT

 public:
  struct Result {
    bool started = true;      // false: the program could not be started
    int exit_code = 0;
    bool crashed = false;     // killed by a signal or crashed
    bool cancelled = false;   // Cancel() was called
    bool saw_result = false;  // it printed a RESULT line
    bool saw_protocol = false;  // it printed any line of the installer protocol
    QString start_error;
    QStringList stderr_tail;  // the last of what it printed on stderr
  };

  explicit DriverProcess(QObject* parent = nullptr);
  ~DriverProcess() override;

  void Start(const QString& program, const QStringList& arguments,
             const QProcessEnvironment& env, const QString& working_directory);
  // Asks it and its children to stop (SIGTERM), kills them after a few seconds.
  void Cancel();
  bool IsRunning() const { return process_ && process_->state() != QProcess::NotRunning; }

 signals:
  void EventReceived(const Event& event);
  void RawLine(const QString& line);  // every stdout line, as printed
  void Finished(const DriverProcess::Result& result);

 private:
  void ReadStdout();
  void ReadStderr();
  void KillGroup(int signal_number);

  QProcess* process_ = nullptr;
  QByteArray out_buffer_;
  QByteArray err_buffer_;
  Result result_;
  QTimer kill_timer_;
  bool reported_ = false;
};

Q_DECLARE_METATYPE(DriverProcess::Result)
