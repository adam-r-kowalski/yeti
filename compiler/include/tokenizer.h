#pragma once

#include <stdint.h>

typedef struct {
  uint32_t line;
  uint32_t column;
} position_t;

typedef struct {
  position_t begin;
  position_t end;
} span_t;

typedef struct {
  span_t span;
} token_t;

token_t *tokenize(const char *input);
