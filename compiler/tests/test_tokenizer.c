#define MUNIT_ENABLE_ASSERT_ALIASES

#include "tokenizer.h"
#include <munit.h>
#include <stdbool.h>
#include <stdint.h>

void assert_position_equal(Position expected, Position actual) {
  assert_uint32(expected.line, ==, actual.line);
  assert_uint32(expected.column, ==, actual.column);
}

void assert_span_equal(Span expected, Span actual) {
  assert_position_equal(expected.begin, actual.begin);
  assert_position_equal(expected.end, actual.end);
}

void assert_cursor_equal(Cursor expected, Cursor actual) {
  assert_position_equal(expected.position, actual.position);
  assert_string_equal(expected.input, actual.input);
}

void assert_string_view_equal(StringView expected, StringView actual) {
  assert_size(expected.length, ==, actual.length);
  assert_memory_equal(expected.length, expected.data, actual.data);
}

void assert_symbol_equal(Symbol expected, Symbol actual) {
  assert_span_equal(expected.span, actual.span);
  assert_string_view_equal(expected.view, actual.view);
}

void assert_int_equal(Int expected, Int actual) {
  assert_span_equal(expected.span, actual.span);
  assert_string_view_equal(expected.view, actual.view);
}

void assert_float_equal(Float expected, Float actual) {
  assert_span_equal(expected.span, actual.span);
  assert_string_view_equal(expected.view, actual.view);
}

void assert_end_of_file_equal(EndOfFile expected, EndOfFile actual) {
  assert_span_equal(expected.span, actual.span);
}

void assert_token_equal(Token expected, Token actual) {
  assert_uint32(expected.type, ==, actual.type);
  switch (expected.type) {
  case SymbolToken:
    return assert_symbol_equal(expected.value.symbol, actual.value.symbol);
  case IntToken:
    return assert_int_equal(expected.value.int_, actual.value.int_);
  case FloatToken:
    return assert_float_equal(expected.value.float_, actual.value.float_);
  case EndOfFileToken:
    return assert_end_of_file_equal(expected.value.end_of_file,
                                    actual.value.end_of_file);
  default:
    assert_true(false);
  }
}

void assert_next_token_result_equal(NextTokenResult expected,
                                    NextTokenResult actual) {
  assert_cursor_equal(expected.cursor, actual.cursor);
  assert_token_equal(expected.token, actual.token);
}

MunitResult tokenize_symbol(const MunitParameter params[],
                            void *user_data_or_fixture) {
  Cursor cursor = {.input = "snake_case camelCase PascalCase "
                            "_leading_underscore trailing_underscore_ "
                            "trailing_number_123"};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span.end = {.column = 10},
                               .view = {.data = "snake_case", .length = 10}},
          },
      .cursor = (Cursor){.input = " camelCase PascalCase "
                                  "_leading_underscore trailing_underscore_ "
                                  "trailing_number_123",
                         .position.column = 10}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 11},
                                        .end = {.column = 20}},
                               .view = {.data = "camelCase", .length = 9}},
          },
      .cursor = (Cursor){.input = " PascalCase "
                                  "_leading_underscore trailing_underscore_ "
                                  "trailing_number_123",
                         .position.column = 20}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 21},
                                        .end = {.column = 31}},
                               .view = {.data = "PascalCase", .length = 10}},
          },
      .cursor = (Cursor){.input = " _leading_underscore trailing_underscore_ "
                                  "trailing_number_123",
                         .position.column = 31}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 32},
                                        .end = {.column = 51}},
                               .view = {.data = "_leading_underscore",
                                        .length = 19}},
          },
      .cursor = (Cursor){.input = " trailing_underscore_ trailing_number_123",
                         .position.column = 51}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 52},
                                        .end = {.column = 72}},
                               .view = {.data = "trailing_underscore_",
                                        .length = 20}},
          },
      .cursor =
          (Cursor){.input = " trailing_number_123", .position.column = 72}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 73},
                                        .end = {.column = 92}},
                               .view = {.data = "trailing_number_123",
                                        .length = 19}},
          },
      .cursor = (Cursor){.input = "", .position.column = 92}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.symbol = {.span = {.begin = {.column = 92},
                                        .end = {.column = 92}},
                               .view = {.data = "", .length = 0}},
          },
      .cursor = (Cursor){.input = "", .position.column = 92}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitResult tokenize_int(const MunitParameter params[],
                         void *user_data_or_fixture) {
  Cursor cursor = {.input = "0 42 -323"};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = IntToken,
              .value.int_ = {.span.end = {.column = 1},
                             .view = {.data = "0", .length = 1}},
          },
      .cursor = (Cursor){.input = " 42 -323", .position.column = 1}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = IntToken,
              .value.int_ = {.span = {.begin = {.column = 2},
                                      .end = {.column = 4}},
                             .view = {.data = "42", .length = 2}},
          },
      .cursor = (Cursor){.input = " -323", .position.column = 4}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.int_ = {.span = {.begin = {.column = 5},
                                      .end = {.column = 6}},
                             .view = {.data = "-", .length = 1}},
          },
      .cursor = (Cursor){.input = "", .position.column = 6}};
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = IntToken,
              .value.int_ = {.span = {.begin = {.column = 6},
                                      .end = {.column = 9}},
                             .view = {.data = "323", .length = 3}},
          },
      .cursor = (Cursor){.input = "", .position.column = 9}};
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file = {.span = {.begin = {.column = 9},
                                             .end = {.column = 9}}},
          },
      .cursor = (Cursor){.input = "", .position.column = 9}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitResult tokenize_float(const MunitParameter params[],
                           void *user_data_or_fixture) {
  Cursor cursor = {.input = "0.0 4.2 .42 -3.23 -.323"};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = FloatToken,
              .value.int_ = {.span.end = {.column = 3},
                             .view = {.data = "0.0", .length = 3}},
          },
      .cursor =
          (Cursor){.input = " 4.2 .42 -3.23 -.323", .position.column = 3}};
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitTest tests[] = {{
                         .name = "/tokenize_symbol",
                         .test = tokenize_symbol,
                     },
                     {
                         .name = "/tokenize_int",
                         .test = tokenize_int,
                     },
                     {
                         .name = "/tokenize_float",
                         .test = tokenize_float,
                     },
                     {}};

static const MunitSuite suite = {
    .prefix = "/tests",
    .tests = tests,
    .iterations = 1,
};

int32_t main(int argc, char *argv[]) {
  return munit_suite_main(&suite, NULL, argc, argv);
}
