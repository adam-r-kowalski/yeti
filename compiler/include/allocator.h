#pragma once

#include <stddef.h>

typedef struct {
  void *(*allocate)(void *state, size_t size, size_t alignment);
  void *state;
} Allocator;

#ifdef YETI_ENABLE_ALLOCATOR_MACROS

#define allocate(allocator, type)                                              \
  (type *)allocator.allocate(allocator.state, sizeof(type), _Alignof(type))

#endif
