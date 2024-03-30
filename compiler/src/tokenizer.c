#include "tokenizer.h"
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>

typedef struct {
  Cursor cursor;
  StringView view;
} TakeWhileResult;

TakeWhileResult take_while_stateful(Cursor cursor,
                                    bool (*predicate)(char, void *),
                                    void *state) {
  const char *input = cursor.input;
  for (; input != NULL; ++input) {
    if (!predicate(*input, state)) {
      break;
    }
  }
  const size_t length = input - cursor.input;
  return (TakeWhileResult){
      .cursor =
          {
              .input = input,
              .position =
                  {
                      .line = cursor.position.line,
                      .column = cursor.position.column + length,
                  },
          },
      .view =
          {
              .data = cursor.input,
              .length = length,
          },
  };
}

bool matches_predicate(char c, void *state) {
  bool (*predicate)(char) = state;
  return predicate(c);
}

TakeWhileResult take_while(Cursor cursor, bool (*predicate)(char)) {
  return take_while_stateful(cursor, matches_predicate, predicate);
}

bool is_space(char c) { return c == ' '; }

Cursor trim_whitespace(Cursor cursor) {
  TakeWhileResult result = take_while(cursor, is_space);
  return result.cursor;
}

bool is_valid_for_symbol(char c) {
  switch (c) {
  case 'a' ... 'z':
  case 'A' ... 'Z':
  case '0' ... '9':
  case '_':
    return true;
  default:
    return false;
  }
}

NextTokenResult symbol_token(Cursor cursor) {
  Position begin = cursor.position;
  TakeWhileResult result = take_while(cursor, is_valid_for_symbol);
  return (NextTokenResult){
      .token =
          {
              .type = SymbolToken,
              .value.symbol =
                  {
                      .span = {.begin = begin, .end = result.cursor.position},
                      .view = result.view,
                  },
          },
      .cursor = result.cursor,
  };
}

bool is_number(char c, void *state) {
  switch (c) {
  case '0' ... '9':
    return true;
  case '.': {
    size_t *decimals = state;
    *decimals += 1;
    return true;
  }
  default:
    return false;
  }
}

NextTokenResult number_token(Cursor cursor) {
  Position begin = cursor.position;
  size_t decimals = 0;
  TakeWhileResult result = take_while_stateful(cursor, is_number, &decimals);
  Span span = {.begin = begin, .end = result.cursor.position};
  switch (decimals) {
  case 0:
    return (NextTokenResult){
        .token =
            {
                .type = IntToken,
                .value.int_ = {.span = span, .view = result.view},
            },
        .cursor = result.cursor,
    };
  case 1:
    return (NextTokenResult){
        .token =
            {
                .type = FloatToken,
                .value.float_ = {.span = span, .view = result.view},
            },
        .cursor = result.cursor,
    };
  default:
    assert(false);
  }
}

NextTokenResult operator_token(Cursor cursor, OperatorKind kind,
                               size_t length) {
  Position begin = cursor.position;
  cursor = (Cursor){.input = cursor.input + length,
                    .position = {.line = cursor.position.line,
                                 .column = cursor.position.column + length}};
  return (NextTokenResult){
      .token =
          {
              .type = OperatorToken,
              .value.operator= {
                  .span = {.begin = begin, .end = cursor.position},
                  .kind = kind,
              },
          },
      .cursor = cursor,
  };
}

NextTokenResult delimiter_token(Cursor cursor, DelimiterKind kind) {
  Position begin = cursor.position;
  cursor = (Cursor){.input = cursor.input + 1,
                    .position = {.line = cursor.position.line,
                                 .column = cursor.position.column + 1}};
  return (NextTokenResult){
      .token =
          {
              .type = DelimiterToken,
              .value.delimiter =
                  {
                      .span = {.begin = begin, .end = cursor.position},
                      .kind = kind,
                  },
          },
      .cursor = cursor,
  };
}

NextTokenResult end_of_file_token(Cursor cursor) {
  return (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file.span = {.begin = cursor.position,
                                         .end = cursor.position},
          },
      .cursor = cursor,
  };
}

NextTokenResult next_token(Cursor cursor) {
  cursor = trim_whitespace(cursor);
  if (*cursor.input == '\0') {
    return end_of_file_token(cursor);
  }
  switch (*cursor.input) {
  case 'a' ... 'z':
  case 'A' ... 'Z':
  case '_':
    return symbol_token(cursor);
  case '0' ... '9':
  case '.':
    return number_token(cursor);
  case '-':
    return operator_token(cursor, SubOperator, 1);
  case '+':
    return operator_token(cursor, AddOperator, 1);
  case '*':
    return operator_token(cursor, MulOperator, 1);
  case '/':
    return operator_token(cursor, DivOperator, 1);
  case '%':
    return operator_token(cursor, ModOperator, 1);
  case '=':
    if (*(cursor.input + 1) == '=') {
      return operator_token(cursor, EqOperator, 2);
    }
    return operator_token(cursor, DefOperator, 1);
  case '!':
    if (*(cursor.input + 1) == '=') {
      return operator_token(cursor, NeOperator, 2);
    }
    return operator_token(cursor, NotOperator, 1);
  case '<':
    if (*(cursor.input + 1) == '=') {
      return operator_token(cursor, LeOperator, 2);
    }
    return operator_token(cursor, LtOperator, 1);
  case '>':
    if (*(cursor.input + 1) == '=') {
      return operator_token(cursor, GeOperator, 2);
    }
    return operator_token(cursor, GtOperator, 1);
  case '[':
    return delimiter_token(cursor, OpenSquareDelimiter);
  case '{':
    return delimiter_token(cursor, OpenCurlyDelimiter);
  case '(':
    return delimiter_token(cursor, OpenParenDelimiter);
  case ')':
    return delimiter_token(cursor, CloseParenDelimiter);
  case '}':
    return delimiter_token(cursor, CloseCurlyDelimiter);
  case ']':
    return delimiter_token(cursor, CloseSquareDelimiter);
  case ',':
    return delimiter_token(cursor, CommaDelimiter);
  default:
    assert(false);
  }
}
