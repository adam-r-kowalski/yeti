#pragma once

#include <stddef.h>
#include <stdint.h>

typedef struct {
  uint8_t *base;
  uint8_t *current_position;
  size_t total_size;
} StackAllocator;

void *stack_allocate(void *allocator, size_t size, size_t alignment);

void stack_allocator_init(StackAllocator *stack, size_t total_size);

void stack_allocator_reset(StackAllocator *stack);

void stack_allocator_destroy(StackAllocator *stack);
