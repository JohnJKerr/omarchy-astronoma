"""Bounded subprocess execution shared by agents and the desktop launcher."""

import os
import selectors
import signal
import subprocess
import time


def _stop_group(process: subprocess.Popen, grace: float) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    # The leader exiting does not mean its descendants exited. Give the
    # whole group a grace period, then kill survivors even if wait() succeeds.
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        process.poll()
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.02)
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def run_bounded(argv: list[str], workdir: str, timeout: float = 180,
                 stdout_limit: int = 256 * 1024,
                 stderr_limit: int = 64 * 1024,
                 termination_grace: float = 2) -> tuple[int, bytes, bytes]:
    """Drain bounded output while the producer runs, with a process-group deadline."""
    # QML's Process can leave stdin as an open pipe. Codex treats piped stdin
    # as additional prompt input even when a positional prompt was supplied,
    # so inheriting that descriptor makes it wait forever for EOF. These are
    # deliberately non-interactive jobs: give every child an immediate EOF.
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               cwd=workdir, start_new_session=True)

    def cancelled(signum, _frame):
        raise SystemExit(128 + signum)

    previous_handlers = {}
    selector = None
    buffers = {process.stdout: bytearray(), process.stderr: bytearray()}
    limits = {process.stdout: stdout_limit, process.stderr: stderr_limit}
    deadline = time.monotonic() + timeout
    try:
        # Install cleanup routing only after Popen succeeds, but inside the
        # protected region: selector or signal setup can fail too.
        for signum in (signal.SIGTERM, signal.SIGINT):
            previous = signal.getsignal(signum)
            signal.signal(signum, cancelled)
            previous_handlers[signum] = previous
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        selector.register(process.stderr, selectors.EVENT_READ)
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise subprocess.TimeoutExpired(argv, timeout)
            for key, _ in selector.select(min(remaining, 0.25)):
                stream = key.fileobj
                chunk = os.read(stream.fileno(), 65536)
                if not chunk:
                    selector.unregister(stream)
                    continue
                buffers[stream].extend(chunk)
                if len(buffers[stream]) > limits[stream]:
                    raise ValueError("process output exceeded the byte limit")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise subprocess.TimeoutExpired(argv, timeout)
        return (process.wait(timeout=remaining), bytes(buffers[process.stdout]),
                bytes(buffers[process.stderr]))
    finally:
        # A second cancellation during teardown must not interrupt TERM/KILL
        # and leave the child tree orphaned. Restore the caller's handlers
        # only after cleanup has completed.
        for signum in previous_handlers:
            try:
                signal.signal(signum, signal.SIG_IGN)
            except ValueError:
                pass
        if selector is not None:
            try:
                selector.close()
            except OSError:
                pass
        for stream in (process.stdout, process.stderr):
            try:
                stream.close()
            except OSError:
                pass
        try:
            _stop_group(process, termination_grace)
        finally:
            for signum, handler in previous_handlers.items():
                try:
                    signal.signal(signum, handler)
                except ValueError:
                    pass
