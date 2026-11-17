#!/usr/bin/env python3
"""Open Claude Code in a fake terminal and record everything it draws.

Usage:
  python3 -I ptyrun.py OUTPUT SECONDS [CLAUDE ARGS...]

Claude Code runs in the current directory, in a 120 x 40 window, for SECONDS,
and is then ended with SIGTERM. Every byte it wrote goes to OUTPUT. The script
then reports where background color writes (OSC 11 and OSC 111) landed, and
whether any of them split a UTF-8 character, which is what garbles a line.

Opening Claude Code without sending a prompt makes no model request.

Examples:
  python3 -I ptyrun.py opening-default.bin 6
  python3 -I ptyrun.py opening-fable.bin 7 --model fable
"""

import fcntl
import math
import os
import pty
import re
import select
import shutil
import signal
import struct
import sys
import termios
import time

COLUMNS, ROWS = 120, 40
EXIT_EXEC_FAILED = 127
OSC_BACKGROUND = re.compile(rb'\x1b\]11;[^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\]111(?:\x07|\x1b\\)')
TERMINATION_GRACE_SECONDS = 2


def answer_terminal_queries(fd, data):
    """Answers the terminal queries Claude Code sends, so startup does not wait."""
    if b'\x1b[c' in data:
        os.write(fd, b'\x1b[?62;22c')
    if b'\x1b]11;?' in data:
        os.write(fd, b'\x1b]11;rgb:1e1e/1e1e/1e1e\x07')


def record(seconds, claude_args):
    """Runs Claude Code in a fake terminal for the given seconds and returns every byte it wrote."""
    pid, fd = pty.fork()
    # The child execs before coverage can save its data.
    if pid == 0:  # pragma: no cover
        os.environ['TERM'] = os.environ.get('TERM', 'xterm-256color')
        try:
            os.execvp('claude', ['claude', *claude_args])
        except OSError:
            os._exit(EXIT_EXEC_FAILED)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', ROWS, COLUMNS, 0, 0))
    out = bytearray()

    def read_for(duration, answer_queries):
        """Collects what the child draws until the duration ends or the terminal closes."""
        end = time.time() + duration
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.1)
            if not ready:
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                return
            # Only macOS signals the end of a pty this way; Linux raises OSError, and the gate runs on Linux.
            if not data:  # pragma: no cover
                return
            out.extend(data)
            if answer_queries:
                answer_terminal_queries(fd, data)

    read_for(seconds, answer_queries=True)
    os.kill(pid, signal.SIGTERM)
    read_for(TERMINATION_GRACE_SECONDS, answer_queries=False)
    os.close(fd)
    return bytes(out)


def splits_utf8(data, start, end):
    """True if the bytes around [start, end) are the two halves of one UTF-8 character."""
    before = data[start - 1] if start > 0 else 0
    after = data[end] if end < len(data) else 0
    opens_character = before & 0xC0 == 0xC0
    inside_character = before & 0x80 and after & 0xC0 == 0x80
    return bool(opens_character or inside_character)


def describe_write(data, write):
    """Returns the report lines of one background color write, given as a regex match over the data."""
    kind = 'reset (OSC 111)' if write.group().startswith(b'\x1b]111') else 'set (OSC 11)'
    broken = splits_utf8(data, write.start(), write.end())
    return [
        f'  {kind} at byte {write.start()}: {"SPLITS A CHARACTER" if broken else "clean"}',
        f'    before: {data[max(0, write.start() - 16) : write.start()]!r}',
        f'    after:  {data[write.end() : write.end() + 16]!r}',
    ]


def background_write_report(data):
    """Returns the report lines of every background color write found in the recorded bytes."""
    writes = list(OSC_BACKGROUND.finditer(data))
    lines = [f'background color writes: {len(writes)}']
    for write in writes:
        lines.extend(describe_write(data, write))
    return lines


def parse_seconds(text):
    """Returns the recording time, or None unless the text is a positive and finite number."""
    try:
        seconds = float(text)
    except ValueError:
        return None
    return seconds if seconds > 0 and math.isfinite(seconds) else None


def parse_args(arguments):
    """Returns (output, seconds, claude_args), or exits with the usage text when they are not valid."""
    if len(arguments) < 2:
        sys.exit(__doc__)
    seconds = parse_seconds(arguments[1])
    if seconds is None or not arguments[0]:
        sys.exit(__doc__)
    return arguments[0], seconds, arguments[2:]


def check_environment(output):
    """Exits with a message when the run could only fail: no Claude Code to open, or nowhere to write the output."""
    if shutil.which('claude') is None:
        sys.exit('error: claude not found on PATH')
    folder = os.path.dirname(output) or '.'
    if not os.path.isdir(folder):
        sys.exit(f'error: folder not found: {folder}')


def write_output(output, data):
    """Writes the recorded bytes, turning a failed write into a message with no traceback."""
    try:
        with open(output, 'wb') as f:
            f.write(data)
    except OSError as error:
        sys.exit(f'error: cannot write {output}: {error.strerror}')


def main(arguments):
    """Records one run and prints where the bytes went and the report of its background color writes."""
    output, seconds, claude_args = parse_args(arguments)
    check_environment(output)
    data = record(seconds, claude_args)
    write_output(output, data)
    print(f'{len(data)} bytes written to {output}')
    print('\n'.join(background_write_report(data)))


if __name__ == '__main__':
    main(sys.argv[1:])
