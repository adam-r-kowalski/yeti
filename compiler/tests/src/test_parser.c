#define MUNIT_ENABLE_ASSERT_ALIASES

#include "test_suites.h"
#include <munit.h>
#include <stdbool.h>

MunitResult parse_symbol(const MunitParameter params[],
                         void *user_data_or_fixture) {
  assert_true(true);
  return MUNIT_OK;
}

MunitTest parser_tests[] = {{
                                .name = "/parse_symbol",
                                .test = parse_symbol,
                            },
                            {}};

MunitSuite parser_suite = {
    .prefix = "/parser",
    .tests = parser_tests,
    .iterations = 1,
};
