#include "CZip.h"
#include <zlib.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
struct cz_cancel { atomic_bool value; };
cz_cancel *cz_cancel_create(void) {
    cz_cancel *t = malloc(sizeof(*t));
    if (t) atomic_init(&t->value, 0);
    return t;
}
void cz_cancel_set(cz_cancel *t) { if (t) atomic_store(&t->value, 1); }
int cz_cancelled(cz_cancel *t) { return t && atomic_load(&t->value); }
void cz_cancel_free(cz_cancel *t) { free(t); }
uint32_t cz_crc(const void *p, unsigned int n) { return (uint32_t)crc32(0, p, n); }
int cz_deflate(int input, int output, cz_cancel *token, uint32_t *crc, uint32_t *size, uint32_t *compressed) {
    unsigned char in[65536], out[65536];
    z_stream z = {0};
    if (deflateInit2(&z, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) return 4;
    uint64_t total = 0, packed = 0;
    uLong checksum = crc32(0, Z_NULL, 0);
    int result = 0, status = Z_OK;
    while (status != Z_STREAM_END) {
        if (cz_cancelled(token)) { result = 1; break; }
        ssize_t count;
        do { count = read(input, in, sizeof(in)); } while (count < 0 && errno == EINTR);
        if (count < 0) { result = 3; break; }
        total += count;
        if (total >= UINT32_MAX) { result = 2; break; }
        checksum = crc32(checksum, in, (uInt)count);
        z.next_in = in; z.avail_in = (uInt)count;
        int flush = count == 0 ? Z_FINISH : Z_NO_FLUSH;
        do {
            if (cz_cancelled(token)) { result = 1; break; }
            z.next_out = out; z.avail_out = sizeof(out);
            status = deflate(&z, flush);
            if (status != Z_OK && status != Z_STREAM_END) { result = 4; break; }
            size_t bytes = sizeof(out) - z.avail_out;
            packed += bytes;
            if (packed >= UINT32_MAX) { result = 2; break; }
            size_t done = 0;
            while (done < bytes) {
                ssize_t n = write(output, out + done, bytes - done);
                if (n < 0 && errno == EINTR) continue;
                if (n <= 0) { result = 3; break; }
                done += (size_t)n;
            }
            if (result) break;
        } while (z.avail_out == 0 || (flush == Z_FINISH && status != Z_STREAM_END));
        if (result) break;
    }
    deflateEnd(&z);
    if (!result) { *crc = (uint32_t)checksum; *size = (uint32_t)total; *compressed = (uint32_t)packed; }
    return result;
}
