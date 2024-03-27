#include "tokenizer.h"
#include <assert.h>
#include <stdbool.h>

typedef struct {
  Cursor cursor;
  StringView view;
} TakeWhileResult;

TakeWhileResult take_while(Cursor cursor, bool (*predicate)(char)) {
  const char *input = cursor.input;
  for (; input != NULL; ++input) {
    if (!predicate(*input)) {
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

bool is_number(char c) { return c >= '0' && c <= '9'; }

NextTokenResult number_token(Cursor cursor) {
  Position begin = cursor.position;
  TakeWhileResult result = take_while(cursor, is_number);
  return (NextTokenResult){
      .token =
          {
              .type = IntToken,
              .value.int_ =
                  {
                      .span = {.begin = begin, .end = result.cursor.position},
                      .view = result.view,
                  },
          },
      .cursor = result.cursor,
  };
}

NextTokenResult operator_token(Cursor cursor, OperatorKind kind) {
  Position begin = cursor.position;
  cursor = (Cursor){.input = cursor.input + 1,
                    .position = {.line = cursor.position.line,
                                 .column = cursor.position.column + 1}};
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

NextTokenResult end_of_file_token(Cursor cursor) {
  return (NextTokenResult){
      .token =
          {
              .type = EndOfFileToken,
              .value.end_of_file =
                  {
                      .span = {.begin = cursor.position,
                               .end = cursor.position},
                  },
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
    return number_token(cursor);
  case '-':
    return operator_token(cursor, MinusOperator);
  default:
    assert(false);
  }
}
