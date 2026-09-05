"""Bounded subprocess execution shared by agents and the desktop launcher."""

import os
import selectors
import signal
import subprocess
import time


def _stop_group(process: subprocess.Popen) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    # The leader exiting does not mean its descendants exited. Give the
    # whole group a grace period, then kill survivors even if wait() succeeds.
    deadline = time.monotonic() + 2
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
                 stderr_limit: int = 64 * 1024) -> tuple[int, bytes, bytes]:
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
    for signum in (signal.SIGTERM, signal.SIGINT):
        previous_handlers[signum] = signal.getsignal(signum)
        signal.signal(signum, cancelled)
    selector = selectors.DefaultSelector()
    buffers = {process.stdout: bytearray(), process.stderr: bytearray()}
    limits = {process.stdout: stdout_limit, process.stderr: stderr_limit}
    selector.register(process.stdout, selectors.EVENT_READ)
    selector.register(process.stderr, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    try:
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
        _stop_group(process)
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
        selector.close()
        process.stdout.close()
        process.stderr.close()

