#define MUNIT_ENABLE_ASSERT_ALIASES

#include "test_suites.h"
#include "tokenizer.h"
#include <munit.h>
#include <stdbool.h>

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

void assert_operator_equal(Operator expected, Operator actual) {
  assert_span_equal(expected.span, actual.span);
  assert_uint32(expected.kind, ==, actual.kind);
}

void assert_delimiter_equal(Delimiter expected, Delimiter actual) {
  assert_span_equal(expected.span, actual.span);
  assert_uint32(expected.kind, ==, actual.kind);
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
  case OperatorToken:
    return assert_operator_equal(expected.value.operator,
                                 actual.value.operator);
  case DelimiterToken:
    return assert_delimiter_equal(expected.value.delimiter,
                                  actual.value.delimiter);
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
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = FloatToken,
              .value.int_ = {.span = {.begin = {.column = 4},
                                      .end = {.column = 7}},
                             .view = {.data = "4.2", .length = 3}},
          },
      .cursor = (Cursor){.input = " .42 -3.23 -.323", .position.column = 7}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = FloatToken,
              .value.int_ = {.span = {.begin = {.column = 8},
                                      .end = {.column = 11}},
                             .view = {.data = ".42", .length = 3}},
          },
      .cursor = (Cursor){.input = " -3.23 -.323", .position.column = 11}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 12}, .end = {.column = 13}},
                  .kind = SubOperator},
          },
      .cursor = (Cursor){.input = "3.23 -.323", .position.column = 13}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = FloatToken,
              .value.int_ = {.span = {.begin = {.column = 13},
                                      .end = {.column = 17}},
                             .view = {.data = "3.23", .length = 4}},
          },
      .cursor = (Cursor){.input = " -.323", .position.column = 17}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 18}, .end = {.column = 19}},
                  .kind = SubOperator},
          },
      .cursor = (Cursor){.input = ".323", .position.column = 19}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = FloatToken,
              .value.int_ = {.span = {.begin = {.column = 19},
                                      .end = {.column = 23}},
                             .view = {.data = ".323", .length = 4}},
          },
      .cursor = (Cursor){.input = "", .position.column = 23}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file = {.span = {.begin = {.column = 23},
                                             .end = {.column = 23}}},
          },
      .cursor = (Cursor){.input = "", .position.column = 23}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitResult tokenize_delimiters(const MunitParameter params[],
                                void *user_data_or_fixture) {
  Cursor cursor = {.input = "[{()}],"};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span.end = {.column = 1},
                                  .kind = OpenSquareDelimiter},
          },
      .cursor = (Cursor){.input = "{()}],", .position.column = 1}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 1},
                                           .end = {.column = 2}},
                                  .kind = OpenCurlyDelimiter},
          },
      .cursor = (Cursor){.input = "()}],", .position.column = 2}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 2},
                                           .end = {.column = 3}},
                                  .kind = OpenParenDelimiter},
          },
      .cursor = (Cursor){.input = ")}],", .position.column = 3}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 3},
                                           .end = {.column = 4}},
                                  .kind = CloseParenDelimiter},
          },
      .cursor = (Cursor){.input = "}],", .position.column = 4}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 4},
                                           .end = {.column = 5}},
                                  .kind = CloseCurlyDelimiter},
          },
      .cursor = (Cursor){.input = "],", .position.column = 5}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 5},
                                           .end = {.column = 6}},
                                  .kind = CloseSquareDelimiter},
          },
      .cursor = (Cursor){.input = ",", .position.column = 6}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter = {.span = {.begin = {.column = 6},
                                           .end = {.column = 7}},
                                  .kind = CommaDelimiter},
          },
      .cursor = (Cursor){.input = "", .position.column = 7}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file = {.span = {.begin = {.column = 7},
                                             .end = {.column = 7}}},
          },
      .cursor = (Cursor){.input = "", .position.column = 7}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitResult tokenize_operators(const MunitParameter params[],
                               void *user_data_or_fixture) {
  Cursor cursor = {.input = "- + * / % == != < > <= >="};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = OperatorToken,
              .value.operator= {.span.end = {.column = 1}, .kind = SubOperator},
          },
      .cursor =
          (Cursor){.input = " + * / % == != < > <= >=", .position.column = 1}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 2}, .end = {.column = 3}},
                  .kind = AddOperator},
          },
      .cursor =
          (Cursor){.input = " * / % == != < > <= >=", .position.column = 3}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 4}, .end = {.column = 5}},
                  .kind = MulOperator},
          },
      .cursor =
          (Cursor){.input = " / % == != < > <= >=", .position.column = 5}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 6}, .end = {.column = 7}},
                  .kind = DivOperator},
          },
      .cursor = (Cursor){.input = " % == != < > <= >=", .position.column = 7}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 8}, .end = {.column = 9}},
                  .kind = ModOperator},
          },
      .cursor = (Cursor){.input = " == != < > <= >=", .position.column = 9}};
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 10}, .end = {.column = 12}},
                  .kind = EqOperator},
          },
      .cursor = (Cursor){.input = " != < > <= >=", .position.column = 12}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 13}, .end = {.column = 15}},
                  .kind = NeOperator},
          },
      .cursor = (Cursor){.input = " < > <= >=", .position.column = 15}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 16}, .end = {.column = 17}},
                  .kind = LtOperator},
          },
      .cursor = (Cursor){.input = " > <= >=", .position.column = 17}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 18}, .end = {.column = 19}},
                  .kind = GtOperator},
          },
      .cursor = (Cursor){.input = " <= >=", .position.column = 19}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 20}, .end = {.column = 22}},
                  .kind = LeOperator},
          },
      .cursor = (Cursor){.input = " >=", .position.column = 22}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 23}, .end = {.column = 25}},
                  .kind = GeOperator},
          },
      .cursor = (Cursor){.input = "", .position.column = 25}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file = {.span = {.begin = {.column = 25},
                                             .end = {.column = 25}}},
          },
      .cursor = (Cursor){.input = "", .position.column = 25}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitResult tokenize_variable_definition(const MunitParameter params[],
                                         void *user_data_or_fixture) {
  Cursor cursor = {.input = "f32 x = 42"};
  NextTokenResult actual = next_token(cursor);
  NextTokenResult expected = {
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span.end = {.column = 3},
                               .view = {.data = "f32", .length = 3}},
          },
      .cursor = (Cursor){.input = " x = 42", .position.column = 3}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol = {.span = {.begin = {.column = 4},
                                        .end = {.column = 5}},
                               .view = {.data = "x", .length = 1}},
          },
      .cursor = (Cursor){.input = " = 42", .position.column = 5}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = {.column = 6}, .end = {.column = 7}},
                  .kind = AssignOperator},
          },
      .cursor = (Cursor){.input = " 42", .position.column = 7}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = IntToken,
              .value.int_ = {.span = {.begin = {.column = 8},
                                      .end = {.column = 10}},
                             .view = {.data = "42", .length = 2}},
          },
      .cursor = (Cursor){.input = "", .position.column = 10}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  expected = (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file = {.span = {.begin = {.column = 10},
                                             .end = {.column = 10}}},
          },
      .cursor = (Cursor){.input = "", .position.column = 10}};
  assert_next_token_result_equal(expected, actual);
  actual = next_token(actual.cursor);
  assert_next_token_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitTest tokenizer_tests[] = {{
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
                               {
                                   .name = "/tokenize_delimiters",
                                   .test = tokenize_delimiters,
                               },
                               {
                                   .name = "/tokenize_operators",
                                   .test = tokenize_operators,
                               },
                               {
                                   .name = "/tokenize_variable_definition",
                                   .test = tokenize_variable_definition,
                               },
                               {}};

MunitSuite tokenizer_suite = {
    .prefix = "/tokenizer",
    .tests = tokenizer_tests,
    .iterations = 1,
};
