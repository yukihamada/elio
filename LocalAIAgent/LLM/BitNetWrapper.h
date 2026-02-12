//
//  BitNetWrapper.h
//  LocalAIAgent
//
//  C wrapper for BitNet inference to avoid conflicts with LlamaSwift
//

#ifndef BitNetWrapper_h
#define BitNetWrapper_h

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque types
typedef struct bitnet_model bitnet_model;
typedef struct bitnet_context bitnet_context;
typedef int32_t bitnet_token;

// Model parameters
typedef struct {
    int32_t n_gpu_layers;
    bool use_mmap;
    bool use_mlock;
} bitnet_model_params;

// Context parameters
typedef struct {
    uint32_t n_ctx;
    uint32_t n_batch;
    uint32_t n_threads;
    bool flash_attn;
} bitnet_context_params;

// Sampling parameters
typedef struct {
    float temperature;
    float top_p;
    int32_t top_k;
    float repeat_penalty;
    int32_t repeat_last_n;
} bitnet_sampling_params;

// Initialize default parameters
bitnet_model_params bitnet_model_default_params(void);
bitnet_context_params bitnet_context_default_params(void);
bitnet_sampling_params bitnet_sampling_default_params(void);

// Model loading/unloading
bitnet_model* bitnet_load_model(const char* path, bitnet_model_params params);
void bitnet_free_model(bitnet_model* model);

// Context creation/destruction
bitnet_context* bitnet_new_context(bitnet_model* model, bitnet_context_params params);
void bitnet_free_context(bitnet_context* ctx);

// Tokenization
int32_t bitnet_tokenize(bitnet_model* model, const char* text, bitnet_token* tokens, int32_t n_max_tokens, bool add_bos);
const char* bitnet_token_to_piece(bitnet_model* model, bitnet_token token);

// Generation
bool bitnet_eval(bitnet_context* ctx, const bitnet_token* tokens, int32_t n_tokens, int32_t n_past);
bitnet_token bitnet_sample(bitnet_context* ctx, bitnet_sampling_params params);

// Special tokens
bitnet_token bitnet_token_bos(bitnet_model* model);
bitnet_token bitnet_token_eos(bitnet_model* model);

// Model info
int32_t bitnet_n_vocab(bitnet_model* model);
int32_t bitnet_n_ctx_train(bitnet_model* model);

// Utility
void bitnet_backend_init(void);
void bitnet_backend_free(void);

#ifdef __cplusplus
}
#endif

#endif /* BitNetWrapper_h */
