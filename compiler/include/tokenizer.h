#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint32_t line;
  uint32_t column;
} Position;

typedef struct {
  Position begin;
  Position end;
} Span;

typedef struct {
  const char *data;
  size_t length;
} StringView;

typedef struct {
  Span span;
  StringView view;
} Symbol;

typedef struct {
  Span span;
  StringView view;
} Float;

typedef struct {
  Span span;
  StringView view;
} Int;

typedef enum {
  SubOperator,
  AddOperator,
  MulOperator,
  DivOperator,
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
} EndOfFile;

typedef enum {
  SymbolToken,
  FloatToken,
  IntToken,
  OperatorToken,
  DelimiterToken,
  EndOfFileToken,
} TokenType;

typedef union {
  Symbol symbol;
  Float float_;
  Int int_;
  Operator operator;
  Delimiter delimiter;
  EndOfFile end_of_file;
} TokenValue;

typedef struct {
  TokenType type;
  TokenValue value;
} Token;

typedef struct {
  Position position;
  const char *input;
} Cursor;

typedef struct {
  Cursor cursor;
  Token token;
} NextTokenResult;

NextTokenResult next_token(Cursor cursor);
