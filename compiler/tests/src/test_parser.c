#include "assertions.h"
#include "parser.h"
#include "test_suites.h"

MunitResult parse_variable_definition(const MunitParameter params[],
                                      void *user_data_or_fixture) {
  Cursor cursor = {.input = "f32 x = 3.14"};
  ParseExpressionResult actual = parse_expression(cursor);
  ParseExpressionResult
      expected =
          {
              .expression =
                  {
                      .kind = AssignExpression,
                      .value
                          .assign = {.type =
                                         &(Expression){
                                             .kind = SymbolExpression,
                                             .value.symbol =
                                                 {
                                                     .span = {.end = {.column = 3,
                                                                      .line = 0}},
                                                     .view = {.data = "f32", .length = 3},
                                                 },
                                         },
                                     .name =
                                         {
                                             .span = {.begin = {.column = 5},
                                                      .end = {.column = 6}},
                                             .view = {.data = "x", .length = 1},
                                         },
                                     .assign_token = {.begin = {.column = 7},
                                                      .end = {.column = 8}},
                                     .value =
                                         &(Expression){
                                             .kind = FloatExpression,
                                             .value.float_ = {
                                                  .span = {.begin = {.column = 10},
                                                            .end = {.column = 13}},
                                                  .view = {.data = "3.14", .length = 4},
            },
                                         }},
                  },
              .cursor =
                  {
                      .input = "",
                      .position = {.column = 13},
                  },
      };
  assert_parse_expression_result_equal(expected, actual);
  return MUNIT_OK;
}

MunitTest parser_tests[] = {{
                                .name = "/parse_symbol",
                                .test = parse_variable_definition,
                            },
                            {}};

MunitSuite parser_suite = {
    .prefix = "/parser",
    .tests = parser_tests,
    .iterations = 1,
};
