#include "test_suites.h"
#include <munit.h>

int32_t main(int argc, char *argv[]) {
  return munit_suite_main(&tokenizer_suite, NULL, argc, argv);
}
