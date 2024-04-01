#define YETI_ENABLE_DEFER_MACROS

#include "assertions.h"
#include "parser.h"
#include "stack_allocator.h"
#include "test_suites.h"

MunitResult parse_variable_definition(const MunitParameter params[],
                                      void *user_data_or_fixture) {
  StackAllocator stack;
  stack_allocator_init(&stack, 2 << 7);
  Allocator allocator = {.allocate = stack_allocate, .state = &stack};
  Cursor cursor = {.input = "f32 x = 42"};
  ParseExpressionResult actual = parse_expression(allocator, cursor);
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
                                             .span = {.begin = {.column = 4},
                                                      .end = {.column = 5}},
                                             .view = {.data = "x", .length = 1},
                                         },
                                     .assign_token = {.begin = {.column = 6},
                                                      .end = {.column = 7}},
                                     .value =
                                         &(Expression){
                                             .kind = FloatExpression,
                                             .value.float_ = {.span =
                                                                  {
                                                                      .begin =
                                                                          {.column = 8},
                                                                      .end = {.column =
                                                                                  10}},
                                                              .view = {.data =
                                                                           "3."
                                                                           "14",
                                                                       .length =
                                                                           4}},
                                         }},
                  },
              .cursor =
                  {
                      .input = "",
                      .position = {.column = 10},
                  },
          };
  assert_parse_expression_result_equal(expected, actual);
  stack_allocator_destroy(&stack);
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
