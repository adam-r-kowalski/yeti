#include "stack_allocator.h"
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

size_t align_forward_adjustment(const void *address, size_t alignment) {
  size_t adjustment = alignment - ((size_t)address & (alignment - 1));
  if (adjustment == alignment) {
    return 0; // Already aligned
  }
  return adjustment;
}

void *stack_allocate(void *allocator, size_t size, size_t alignment) {
  printf("\n\n===stack_allocate(size: %zu, alignment: %zu)===\n\n", size, alignment);
  StackAllocator *stack = (StackAllocator *)allocator;
  size_t adjustment = align_forward_adjustment(stack->current_position, alignment);

  // Check if there's enough space for the adjustment plus the requested size without underflow
  size_t spaceNeeded = size + adjustment;
  size_t spaceLeft = stack->total_size - (stack->current_position - stack->base);

  if (spaceLeft < spaceNeeded) {
    // Handle out-of-memory error (e.g., by logging an error or exiting the program)
    printf("\n\n=== Out of memory ===\n\n");
    assert(false); // This will now correctly trigger if there isn't enough memory
    return NULL; // It's good practice to return NULL if the allocation fails
  }

  void *aligned_address = stack->current_position + adjustment;
  stack->current_position = (uint8_t *)aligned_address + size;
  return aligned_address;
}

void stack_allocator_init(StackAllocator *stack, size_t total_size) {
  printf("\n\n===stack_allocator_init(total_size: %zu)===\n\n", total_size);
  stack->base =
      (uint8_t *)malloc(total_size); // Allocate the total required memory
  if (stack->base == nullptr) {
    // Handle memory allocation failure (e.g., by logging an error or exiting
    // the program)
    assert(false);
  }
  stack->current_position =
      stack->base; // Initial position is at the base of the stack
  stack->total_size =
      total_size; // Store the total size of the allocated memory area
}

void stack_allocator_reset(StackAllocator *stack) {
  stack->current_position =
      stack->base; // Reset the current position to the base of the stack
}

void stack_allocator_destroy(StackAllocator *stack) {
  free(stack->base); // Free the allocated memory area when the allocator is no
                     // longer needed
}
