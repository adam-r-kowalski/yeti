#define MUNIT_ENABLE_ASSERT_ALIASES
#define YETI_ENABLE_ALLOCATOR_MACROS

#include "parser.h"
#include <assert.h>
#include <stdbool.h>

ParseExpressionResult parse_symbol(Cursor cursor, Symbol symbol) {
  return (ParseExpressionResult){
      .expression =
          {
              .kind = SymbolExpression,
              .value.symbol = symbol,
          },
      .cursor = cursor,
  };
}

ParseExpressionResult parse_float(Cursor cursor, Float float_) {
  return (ParseExpressionResult){
      .expression =
          {
              .kind = FloatExpression,
              .value.float_ = float_,
          },
      .cursor = cursor,
  };
}

ParseExpressionResult parse_int(Cursor cursor, Int int_) {
  return (ParseExpressionResult){
      .expression =
          {
              .kind = IntExpression,
              .value.int_ = int_,
          },
      .cursor = cursor,
  };
}

ParseExpressionResult parse_prefix(Cursor cursor) {
  NextTokenResult result = next_token(cursor);
  switch (result.token.kind) {
  case SymbolToken:
    return parse_symbol(result.cursor, result.token.value.symbol);
  case FloatToken:
    return parse_float(result.cursor, result.token.value.float_);
  case IntToken:
    return parse_int(result.cursor, result.token.value.int_);
  default:
    assert(false);
  }
}

typedef ParseExpressionResult (*InfixParser)(Allocator, Cursor, Expression,
                                             Token);

ParseExpressionResult parse_define(Allocator allocator, Cursor cursor,
                                   Expression prefix, Token name) {
  NextTokenResult assign_operator = next_token(cursor);
  ParseExpressionResult value =
      parse_expression(allocator, assign_operator.cursor);
  Expression *type = allocate(allocator, Expression);
  if (type == nullptr) {
    // TODO: return an error ast node instead of panicking
    assert(false);
  }
  *type = prefix;
  Expression *assign_value = allocate(allocator, Expression);
  if (assign_value == nullptr) {
    // TODO: return an error ast node instead of panicking
    assert(false);
  }
  *assign_value = value.expression;
  Expression assign = {
      .kind = AssignExpression,
      .value.assign = {.type = type,
                       .name = name.value.symbol,
                       .assign_token =
                           assign_operator.token.value.operator.span,
                       .value = assign_value},
  };
  return (ParseExpressionResult){
      .expression = assign,
      .cursor = value.cursor,
  };
}

typedef struct {
  Expression prefix;
  Token token;
  Cursor cursor;
  InfixParser infix_parser;
} InfixParserForResult;

InfixParserForResult
infix_parser_for(ParseExpressionResult parse_expression_result) {
  ExpressionKind expression_kind = parse_expression_result.expression.kind;
  NextTokenResult next_token_result =
      next_token(parse_expression_result.cursor);
  switch (expression_kind) {
  case SymbolExpression: {
    switch (next_token_result.token.kind) {
    case SymbolToken:
      return (InfixParserForResult){
          .prefix = parse_expression_result.expression,
          .token = next_token_result.token,
          .cursor = next_token_result.cursor,
          .infix_parser = parse_define,
      };
    default:
      return (InfixParserForResult){};
    }
  }
  default:
    return (InfixParserForResult){};
  }
}

ParseExpressionResult parse_infix(Allocator allocator,
                                  InfixParserForResult result) {
  return result.infix_parser(allocator, result.cursor, result.prefix,
                             result.token);
}

ParseExpressionResult parse_expression(Allocator allocator, Cursor cursor) {
  ParseExpressionResult parse_expression_result = parse_prefix(cursor);
  InfixParserForResult infix_parser_for_result =
      infix_parser_for(parse_expression_result);
  while (infix_parser_for_result.infix_parser != nullptr) {
    parse_expression_result = parse_infix(allocator, infix_parser_for_result);
    infix_parser_for_result = infix_parser_for(parse_expression_result);
  }
  return parse_expression_result;
}
