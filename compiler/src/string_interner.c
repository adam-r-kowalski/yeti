#include "string_interner.h"
#include <string.h>

uint32_t hash_string(size_t length, const char string[length]) {
  uint32_t hash = 2166136261U;
  while (*string) {
    hash ^= (uint32_t)(*string++);
    hash *= 16777619;
  }
  return hash;
}

InternResult intern_string(StringInterner *interner, size_t length,
                           const char string[length]) {
  if (length > MAX_STRING_LENGTH) {
    return (InternResult){.status = INTERN_ERROR_TOO_LONG};
  }
  uint32_t hash = hash_string(length, string);
  for (size_t i = 0; i < MAX_STRINGS; i++) {
    size_t index = (hash + i) % MAX_STRINGS;
    if (!interner->occupied[index]) {
      interner->occupied[index] = true;
      memcpy(interner->strings[index], string, length);
      interner->strings[index][length] = '\0';
      interner->lengths[index] = length;
      interner->hashes[index] = hash;
      return (InternResult){
          .status = INTERN_SUCCESS,
          .interned = {.index = index},
      };
    }
    bool found = interner->hashes[index] == hash &&
                 interner->lengths[index] == length &&
                 memcmp(interner->strings[index], string, length) == 0;
    if (found) {
      return (InternResult){
          .status = INTERN_SUCCESS,
          .interned = {.index = index},
      };
    }
  }
  return (InternResult){.status = INTERN_ERROR_FULL};
}

LookupResult lookup_string(const StringInterner *interner, Interned interned) {
  if (interned.index >= MAX_STRINGS || !interner->occupied[interned.index]) {
    return (LookupResult){
        .status = LOOKUP_ERROR_NOT_FOUND,
    };
  }
  return (LookupResult){
      .string = interner->strings[interned.index],
      .status = LOOKUP_SUCCESS,
  };
}
