#pragma once

#include "string_interner.h"
#include <stdint.h>

#define MAX_TOKENS 1024

typedef struct {
  uint32_t line;
  uint32_t column;
} Position;

typedef struct {
  Position begin;
  Position end;
} Span;

typedef struct {
  Span span;
  size_t interned;
} Symbol;

typedef struct {
  Span span;
  size_t interned;
} Float;

typedef struct {
  Span span;
  size_t interned;
} Int;

typedef enum {
  SubOperator,
  AddOperator,
  MulOperator,
  DivOperator,
  ModOperator,
  EqOperator,
  AssignOperator,
  NeOperator,
  NotOperator,
  LtOperator,
  LeOperator,
  GtOperator,
  GeOperator,
} OperatorKind;

typedef struct {
  Span span;
  OperatorKind kind;
} Operator;

typedef enum {
  OpenSquareDelimiter,
  OpenCurlyDelimiter,
  OpenParenDelimiter,
  CloseParenDelimiter,
  CloseCurlyDelimiter,
  CloseSquareDelimiter,
  CommaDelimiter,
} DelimiterKind;

typedef struct {
  Span span;
  DelimiterKind kind;
} Delimiter;

typedef struct {
  Span span;
  size_t message;
  size_t context;
  size_t hint;
} Error;

typedef enum {
  SymbolToken,
  FloatToken,
  IntToken,
  OperatorToken,
  DelimiterToken,
  ErrorToken,
} TokenKind;

typedef struct {
  TokenKind kinds[MAX_TOKENS];
  Symbol symbols[MAX_TOKENS];
  Float floats[MAX_TOKENS];
  Int ints[MAX_TOKENS];
  Operator operators[MAX_TOKENS];
  Delimiter delimiters[MAX_TOKENS];
  Error errors[MAX_TOKENS];
} Tokens;

Tokens tokenize(char *input);
