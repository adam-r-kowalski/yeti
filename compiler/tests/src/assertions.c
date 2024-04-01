#define MUNIT_ENABLE_ASSERT_ALIASES

#include "assertions.h"
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

void assert_parse_expression_result_equal(ParseExpressionResult expected,
                                          ParseExpressionResult actual) {}
