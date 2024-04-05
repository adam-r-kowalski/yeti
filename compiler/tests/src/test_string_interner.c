#define MUNIT_ENABLE_ASSERT_ALIASES

#include "string_interner.h"
#include "test_suites.h"
#include <stdio.h>

MunitResult intern_and_lookup_example(const MunitParameter params[],
                                      void *user_data_or_fixture) {
  StringInterner interner = {0};
  const char *string = "example";
  size_t length = strlen(string);
  InternResult internResult = intern_string(&interner, length, string);
  assert_int(internResult.status, ==, INTERN_SUCCESS);
  LookupResult lookupResult = lookup_string(&interner, internResult.interned);
  assert_int(lookupResult.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(lookupResult.string, string);
  return MUNIT_OK;
}

MunitResult intern_and_lookup_empty_string(const MunitParameter params[],
                                           void *user_data_or_fixture) {
  StringInterner interner = {0};
  const char *string = "";
  size_t length = strlen(string);
  InternResult internResult = intern_string(&interner, length, string);
  assert_int(internResult.status, ==, INTERN_SUCCESS);
  LookupResult lookupResult = lookup_string(&interner, internResult.interned);
  assert_int(lookupResult.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(lookupResult.string, string);
  return MUNIT_OK;
}

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

MunitResult intern_string_and_lookup(const MunitParameter params[],
                                     void *user_data_or_fixture) {
  StringInterner interner = {0};
  char string[MAX_STRING_LENGTH_WITH_NULL];
  size_t length = munit_rand_int_range(1, MAX_STRING_LENGTH);
  random_string(length, string);
  Interned interned = intern_random_string(&interner, length, string);
  LookupResult lookup = lookup_string(&interner, interned);
  assert_int(lookup.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(lookup.string, string);
  return MUNIT_OK;
}

MunitResult intern_two_strings_and_lookup(const MunitParameter params[],
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
  LookupResult first_lookup = lookup_string(&interner, first_interned);
  LookupResult second_lookup = lookup_string(&interner, second_interned);
  assert_int(first_lookup.status, ==, LOOKUP_SUCCESS);
  assert_int(second_lookup.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(first_lookup.string, first_string);
  assert_string_equal(second_lookup.string, second_string);
  return MUNIT_OK;
}

MunitResult intern_till_capacity(const MunitParameter params[],
                                 void *user_data_or_fixture) {
  StringInterner interner = {0};
  char pattern[] = "string_%d";
  char strings[MAX_STRINGS][MAX_STRING_LENGTH_WITH_NULL];
  Interned interned[MAX_STRINGS];
  for (size_t i = 0; i < MAX_STRINGS; i++) {
    char *string = strings[i];
    snprintf(string, MAX_STRING_LENGTH_WITH_NULL, pattern, i);
    InternResult result = intern_string(&interner, strlen(string), string);
    assert_int(result.status, ==, INTERN_SUCCESS);
    interned[i] = result.interned;
  }
  for (size_t i = 0; i < MAX_STRINGS; i++) {
    LookupResult result = lookup_string(&interner, interned[i]);
    assert_int(result.status, ==, LOOKUP_SUCCESS);
    assert_string_equal(result.string, strings[i]);
  }
  char string[MAX_STRING_LENGTH_WITH_NULL];
  snprintf(string, MAX_STRING_LENGTH_WITH_NULL, pattern, MAX_STRINGS);
  InternResult result = intern_string(&interner, strlen(string), string);
  assert_int(result.status, ==, INTERN_ERROR_FULL);
  return MUNIT_OK;
}

MunitResult intern_string_which_is_too_long(const MunitParameter params[],
                                            void *user_data_or_fixture) {
  StringInterner interner = {0};
  size_t length = MAX_STRING_LENGTH + 1;
  char string[length + 1];
  for (size_t i = 0; i < length; i++) {
    string[i] = munit_rand_int_range(' ', '~');
  }
  string[length] = '\0';
  InternResult result = intern_string(&interner, length, string);
  assert_int(result.status, ==, INTERN_ERROR_TOO_LONG);
  return MUNIT_OK;
}

MunitResult lookup_string_which_is_not_there(const MunitParameter params[],
                                             void *user_data_or_fixture) {
  StringInterner interner = {0};
  size_t index = 0;
  assert_int(interner.occupied[index], ==, false);
  Interned interned = {.index = index};
  LookupResult lookupResult = lookup_string(&interner, interned);
  assert_int(lookupResult.status, ==, LOOKUP_ERROR_NOT_FOUND);
  return MUNIT_OK;
}

MunitResult intern_same_string_twice(const MunitParameter params[],
                                     void *user_data_or_fixture) {
  StringInterner interner = {0};
  char string[MAX_STRING_LENGTH_WITH_NULL];
  size_t length = munit_rand_int_range(1, MAX_STRING_LENGTH);
  random_string(length, string);
  Interned interned = intern_random_string(&interner, length, string);
  LookupResult lookup = lookup_string(&interner, interned);
  assert_int(lookup.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(lookup.string, string);
  interned = intern_random_string(&interner, length, string);
  lookup = lookup_string(&interner, interned);
  assert_int(lookup.status, ==, LOOKUP_SUCCESS);
  assert_string_equal(lookup.string, string);
  return MUNIT_OK;
}

MunitTest string_interner_tests[] = {
    {
        .name = "/intern_and_lookup_example",
        .test = intern_and_lookup_example,
    },
    {
        .name = "/intern_string_and_lookup",
        .test = intern_string_and_lookup,
    },
    {
        .name = "/intern_and_lookup_empty_string",
        .test = intern_and_lookup_empty_string,
    },
    {
        .name = "/intern_two_strings_and_lookup",
        .test = intern_two_strings_and_lookup,
    },
    {
        .name = "/intern_till_capacity",
        .test = intern_till_capacity,
    },
    {
        .name = "/intern_string_which_is_too_long",
        .test = intern_string_which_is_too_long,
    },
    {
        .name = "/lookup_string_which_is_not_there",
        .test = lookup_string_which_is_not_there,
    },
    {
        .name = "/intern_same_string_twice",
        .test = intern_same_string_twice,
    },
    {}};

MunitSuite string_interner_suite = {
    .prefix = "/string_interner",
    .tests = string_interner_tests,
    .iterations = 1,
};
