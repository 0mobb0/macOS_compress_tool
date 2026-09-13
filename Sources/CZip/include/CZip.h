#ifndef CZIP_H
#define CZIP_H
#include <stdint.h>
typedef struct cz_cancel cz_cancel;
cz_cancel *cz_cancel_create(void);
void cz_cancel_set(cz_cancel *token);
int cz_cancelled(cz_cancel *token);
void cz_cancel_free(cz_cancel *token);
uint32_t cz_crc(const void *bytes, unsigned int count);
/* 0 success, 1 cancelled, 2 size limit, 3 I/O, 4 deflate failure. */
int cz_deflate(int input, int output, cz_cancel *token, uint32_t *crc, uint32_t *size, uint32_t *compressed);
#endif
