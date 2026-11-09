#include <stdio.h>
#include <string.h>

int main(void) {
  char buf[64] = {0};
  FILE *f = fopen("/app/hello.txt", "rb");
  if (!f) return 10;
  size_t n = fread(buf, 1, sizeof(buf) - 1, f);
  fclose(f);
  if (n != 5 || memcmp(buf, "hello", 5) != 0) return 11;

  FILE *o = fopen("/data/out.txt", "wb");
  if (!o) return 12;
  if (fwrite(buf, 1, n, o) != n) return 13;
  fclose(o);
  return 0;
}
