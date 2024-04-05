#pragma once

#include <stddef.h>
#include <stdint.h>

#define MAX_STRINGS 1024
#define MAX_STRING_LENGTH 100
#define MAX_STRING_LENGTH_WITH_NULL (MAX_STRING_LENGTH + 1)

typedef struct {
  size_t index;
} Interned;

typedef struct {
  uint32_t hashes[MAX_STRINGS];
  uint32_t lengths[MAX_STRINGS];
  char strings[MAX_STRINGS][MAX_STRING_LENGTH_WITH_NULL];
  bool occupied[MAX_STRINGS];
} StringInterner;

typedef enum {
  INTERN_SUCCESS,
  INTERN_ERROR_FULL,
  INTERN_ERROR_TOO_LONG,
} InternStatus;

typedef struct {
  Interned interned;
  InternStatus status;
} InternResult;

InternResult intern_string(StringInterner *interner, size_t length,
                           const char string[length]);

typedef enum {
  LOOKUP_SUCCESS,
  LOOKUP_ERROR_NOT_FOUND,
} LookupStatus;

typedef struct {
  const char *string;
  LookupStatus status;
} LookupResult;

LookupResult lookup_string(const StringInterner *interner, Interned interned);
