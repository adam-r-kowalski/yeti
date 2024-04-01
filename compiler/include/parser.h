#pragma once

#include <tokenizer.h>

typedef enum {
  SymbolExpression,
  FloatExpression,
  AssignExpression,
} ExpressionKind;

typedef struct Expression Expression;

typedef struct {
  Expression *type;
  Symbol name;
  Span assign_token;
  Expression *value;
} Assign;

typedef union {
  Symbol symbol;
  Float float_;
  Assign assign;
} ExpressionValue;

struct Expression {
  ExpressionKind kind;
  Span span;
  ExpressionValue value;
};

typedef struct {
  Expression expression;
  Cursor cursor;
} ParseExpressionResult;

ParseExpressionResult parse_expression(Cursor cursor);
