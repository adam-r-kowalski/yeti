#include <munit.h>
#include <stdint.h>

int32_t main(void) {
  int32_t a = 5;
  int32_t b = 3;
  munit_assert_int(a, ==, b);
  return 0;
}
