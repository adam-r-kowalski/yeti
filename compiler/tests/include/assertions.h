#pragma once

#include "parser.h"

void assert_position_equal(Position expected, Position actual);

void assert_span_equal(Span expected, Span actual);

void assert_cursor_equal(Cursor expected, Cursor actual);

void assert_string_view_equal(StringView expected, StringView actual);

void assert_symbol_equal(Symbol expected, Symbol actual);

void assert_int_equal(Int expected, Int actual);

void assert_float_equal(Float expected, Float actual);

void assert_operator_equal(Operator expected, Operator actual);

void assert_delimiter_equal(Delimiter expected, Delimiter actual);

void assert_end_of_file_equal(EndOfFile expected, EndOfFile actual);

void assert_token_equal(Token expected, Token actual);

void assert_next_token_result_equal(NextTokenResult expected,
                                    NextTokenResult actual);

void assert_assign_expression_equal(Assign expected, Assign actual);

void assert_expression_equal(Expression expected, Expression actual);

void assert_parse_expression_result_equal(ParseExpressionResult expected,
                                          ParseExpressionResult actual);
