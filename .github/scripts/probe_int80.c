/* CI, x86-64 only. A 64-bit program can still make a system call in the 32-bit convention, with "int $0x80".
   There the numbers differ: 359 is socket. A filter that looks only at the 64-bit numbers would let this through.
   Under the lock of setup/claude/no_unix_sockets.py every such call must come back as "not there" (-38).
   Prints: int80-socket=<a file descriptor, or minus the error number> */
#include <stdio.h>

int main(void) {
    long result;
    __asm__ volatile("int $0x80" : "=a"(result) : "a"(359L), "b"(1L), "c"(1L), "d"(0L) : "memory");
    printf("int80-socket=%d\n", (int)result);
    return 0;
}
