#pragma once

#include <allocator.h>
#include <tokenizer.h>

typedef enum {
  SymbolExpression,
  FloatExpression,
  IntExpression,
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
  Int int_;
  Assign assign;
} ExpressionValue;

struct Expression {
  ExpressionKind kind;
  ExpressionValue value;
  Span span;
};

typedef struct {
  Expression expression;
  Cursor cursor;
} ParseExpressionResult;

ParseExpressionResult parse_expression(Allocator allocator, Cursor cursor);
