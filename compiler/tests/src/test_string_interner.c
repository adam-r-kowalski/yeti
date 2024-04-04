#define MUNIT_ENABLE_ASSERT_ALIASES

#include "string_interner.h"
#include "test_suites.h"

void random_string(size_t length, char string[MAX_STRING_LENGTH_WITH_NULL]) {
  assert_int(length, <=, MAX_STRING_LENGTH);
  for (size_t i = 0; i < length; i++) {
    string[i] = munit_rand_int_range(' ', '~');
  }
  string[length] = '\0';
}

Interned intern_random_string(StringInterner *interner, size_t length,
                              char string[MAX_STRING_LENGTH_WITH_NULL]) {
  InternResult result = intern_string(interner, length, string);
  assert_int(result.status, ==, INTERN_SUCCESS);
  return result.interned;
}

MunitResult intern_string_and_retrieve_it(const MunitParameter params[],
                                          void *user_data_or_fixture) {
  StringInterner interner = {0};
  char string[MAX_STRING_LENGTH_WITH_NULL];
  size_t length = munit_rand_int_range(1, MAX_STRING_LENGTH);
  random_string(length, string);
  Interned interned = intern_random_string(&interner, length, string);
  LookupResult retrieved = lookup_string(&interner, interned);
  assert_int(retrieved.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(retrieved.string, string);
  return MUNIT_OK;
}

MunitResult intern_two_strings_and_retrieve_them(const MunitParameter params[],
                                                 void *user_data_or_fixture) {
  StringInterner interner = {0};
  char first_string[MAX_STRING_LENGTH_WITH_NULL];
  char second_string[MAX_STRING_LENGTH_WITH_NULL];
  size_t first_length = munit_rand_int_range(1, MAX_STRING_LENGTH);
  size_t second_length = munit_rand_int_range(1, MAX_STRING_LENGTH);
  random_string(first_length, first_string);
  random_string(second_length, second_string);
  if (strcmp(first_string, second_string) == 0) {
    return MUNIT_SKIP;
  }
  Interned first_interned =
      intern_random_string(&interner, first_length, first_string);
  Interned second_interned =
      intern_random_string(&interner, second_length, second_string);
  LookupResult first_retrieved = lookup_string(&interner, first_interned);
  LookupResult second_retrieved = lookup_string(&interner, second_interned);
  assert_int(first_retrieved.status, ==, LOOKUP_SUCCESS);
  assert_int(second_retrieved.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(first_retrieved.string, first_string);
  assert_string_equal(second_retrieved.string, second_string);
  return MUNIT_OK;
}

MunitTest string_interner_tests[] = {
    {
        .name = "/intern_string_and_retreive_it",
        .test = intern_string_and_retrieve_it,
    },
    {
        .name = "/intern_two_strings_and_retrieve_them",
        .test = intern_two_strings_and_retrieve_them,
    },
    {}};

MunitSuite string_interner_suite = {
    .prefix = "/string_interner",
    .tests = string_interner_tests,
    .iterations = 1,
};
