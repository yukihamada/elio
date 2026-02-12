/**
 * @file agent_context.c
 * @brief Arena allocator implementation
 */

#include "agent_context.h"
#include <stdlib.h>
#include <string.h>

#define DEFAULT_ARENA_SIZE (64 * 1024)  /* 64KB */
#define ALIGNMENT 8

/**
 * @brief Arena block structure
 */
typedef struct arena_block_t {
    struct arena_block_t* next;
    size_t size;
    size_t used;
    char data[];  /* Flexible array member */
} arena_block_t;

/**
 * @brief Agent context with arena allocator
 */
struct agent_context_t {
    arena_block_t* first_block;
    arena_block_t* current_block;
    size_t default_block_size;
    size_t total_allocated;
};

/**
 * @brief Align size to ALIGNMENT boundary
 */
static inline size_t align_size(size_t size) {
    return (size + ALIGNMENT - 1) & ~(ALIGNMENT - 1);
}

/**
 * @brief Create a new arena block
 */
static arena_block_t* arena_block_create(size_t min_size) {
    size_t block_size = min_size > DEFAULT_ARENA_SIZE ? min_size : DEFAULT_ARENA_SIZE;
    arena_block_t* block = (arena_block_t*)malloc(sizeof(arena_block_t) + block_size);
    if (!block) {
        return NULL;
    }
    block->next = NULL;
    block->size = block_size;
    block->used = 0;
    return block;
}

agent_context_t* agent_context_create(size_t initial_size) {
    agent_context_t* ctx = (agent_context_t*)malloc(sizeof(agent_context_t));
    if (!ctx) {
        return NULL;
    }

    size_t block_size = initial_size > 0 ? initial_size : DEFAULT_ARENA_SIZE;
    ctx->first_block = arena_block_create(block_size);
    if (!ctx->first_block) {
        free(ctx);
        return NULL;
    }

    ctx->current_block = ctx->first_block;
    ctx->default_block_size = block_size;
    ctx->total_allocated = sizeof(arena_block_t) + block_size;

    return ctx;
}

void agent_context_destroy(agent_context_t* ctx) {
    if (!ctx) {
        return;
    }

    arena_block_t* block = ctx->first_block;
    while (block) {
        arena_block_t* next = block->next;
        free(block);
        block = next;
    }

    free(ctx);
}

void* agent_context_alloc(agent_context_t* ctx, size_t size) {
    if (!ctx || size == 0) {
        return NULL;
    }

    size_t aligned_size = align_size(size);
    arena_block_t* block = ctx->current_block;

    /* Check if current block has space */
    if (block->used + aligned_size > block->size) {
        /* Need a new block */
        size_t new_block_size = aligned_size > ctx->default_block_size
            ? aligned_size
            : ctx->default_block_size;

        arena_block_t* new_block = arena_block_create(new_block_size);
        if (!new_block) {
            return NULL;
        }

        block->next = new_block;
        ctx->current_block = new_block;
        ctx->total_allocated += sizeof(arena_block_t) + new_block_size;
        block = new_block;
    }

    void* ptr = block->data + block->used;
    block->used += aligned_size;
    return ptr;
}

void* agent_context_calloc(agent_context_t* ctx, size_t count, size_t size) {
    size_t total = count * size;
    void* ptr = agent_context_alloc(ctx, total);
    if (ptr) {
        memset(ptr, 0, total);
    }
    return ptr;
}

void agent_context_reset(agent_context_t* ctx) {
    if (!ctx) {
        return;
    }

    /* Free all blocks except the first one */
    arena_block_t* block = ctx->first_block->next;
    while (block) {
        arena_block_t* next = block->next;
        ctx->total_allocated -= sizeof(arena_block_t) + block->size;
        free(block);
        block = next;
    }

    ctx->first_block->next = NULL;
    ctx->first_block->used = 0;
    ctx->current_block = ctx->first_block;
}

size_t agent_context_savepoint(agent_context_t* ctx) {
    if (!ctx) {
        return 0;
    }
    return ctx->current_block->used;
}

void agent_context_restore(agent_context_t* ctx, size_t savepoint) {
    if (!ctx) {
        return;
    }

    /* Simple restore: just reset the first block's used counter */
    /* This only works correctly if savepoint was taken on the first block */
    /* For a full implementation, we'd need to track which block the savepoint is in */
    if (ctx->current_block == ctx->first_block && savepoint <= ctx->first_block->size) {
        ctx->first_block->used = savepoint;
    }
}

size_t agent_context_used(agent_context_t* ctx) {
    if (!ctx) {
        return 0;
    }

    size_t total = 0;
    arena_block_t* block = ctx->first_block;
    while (block) {
        total += block->used;
        block = block->next;
    }
    return total;
}

size_t agent_context_capacity(agent_context_t* ctx) {
    if (!ctx) {
        return 0;
    }
    return ctx->total_allocated;
}

char* agent_context_strdup(agent_context_t* ctx, const char* str) {
    if (!ctx || !str) {
        return NULL;
    }
    size_t len = strlen(str);
    return agent_context_strndup(ctx, str, len);
}

char* agent_context_strndup(agent_context_t* ctx, const char* str, size_t len) {
    if (!ctx || !str) {
        return NULL;
    }

    char* copy = (char*)agent_context_alloc(ctx, len + 1);
    if (!copy) {
        return NULL;
    }

    memcpy(copy, str, len);
    copy[len] = '\0';
    return copy;
}

agent_string_view_t agent_context_string_view(agent_context_t* ctx, const char* str) {
    agent_string_view_t sv = {NULL, 0};
    if (!ctx || !str) {
        return sv;
    }

    size_t len = strlen(str);
    char* copy = agent_context_strndup(ctx, str, len);
    if (copy) {
        sv.data = copy;
        sv.length = len;
    }
    return sv;
}

agent_string_view_t agent_context_string_view_n(agent_context_t* ctx, const char* str, size_t len) {
    agent_string_view_t sv = {NULL, 0};
    if (!ctx || !str) {
        return sv;
    }

    char* copy = agent_context_strndup(ctx, str, len);
    if (copy) {
        sv.data = copy;
        sv.length = len;
    }
    return sv;
}
