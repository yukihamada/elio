//
//  BitNetWrapper.cpp
//  LocalAIAgent
//
//  C wrapper implementation for BitNet inference
//

#include "BitNetWrapper.h"
#include "llama.h"
#include "ggml.h"

#include <vector>
#include <string>

// Model wrapper
struct bitnet_model {
    llama_model* model;
};

// Context wrapper
struct bitnet_context {
    llama_context* ctx;
    llama_model* model;
    std::vector<llama_token> tokens;
};

// Default parameters
bitnet_model_params bitnet_model_default_params(void) {
    bitnet_model_params params;
    params.n_gpu_layers = 99;  // Offload all layers
    params.use_mmap = true;
    params.use_mlock = false;
    return params;
}

bitnet_context_params bitnet_context_default_params(void) {
    bitnet_context_params params;
    params.n_ctx = 4096;
    params.n_batch = 512;
    params.n_threads = 4;
    params.flash_attn = true;
    return params;
}

bitnet_sampling_params bitnet_sampling_default_params(void) {
    bitnet_sampling_params params;
    params.temperature = 0.7f;
    params.top_p = 0.9f;
    params.top_k = 40;
    params.repeat_penalty = 1.1f;
    params.repeat_last_n = 64;
    return params;
}

// Backend initialization
void bitnet_backend_init(void) {
    llama_backend_init();
}

void bitnet_backend_free(void) {
    llama_backend_free();
}

// Model loading
bitnet_model* bitnet_load_model(const char* path, bitnet_model_params params) {
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = params.n_gpu_layers;
    model_params.use_mmap = params.use_mmap;
    model_params.use_mlock = params.use_mlock;

    llama_model* model = llama_load_model_from_file(path, model_params);
    if (!model) {
        return nullptr;
    }

    bitnet_model* wrapper = new bitnet_model;
    wrapper->model = model;
    return wrapper;
}

void bitnet_free_model(bitnet_model* model) {
    if (model) {
        if (model->model) {
            llama_free_model(model->model);
        }
        delete model;
    }
}

// Context management
bitnet_context* bitnet_new_context(bitnet_model* model, bitnet_context_params params) {
    if (!model || !model->model) {
        return nullptr;
    }

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = params.n_ctx;
    ctx_params.n_batch = params.n_batch;
    ctx_params.n_threads = params.n_threads;
    ctx_params.flash_attn = params.flash_attn;

    llama_context* ctx = llama_new_context_with_model(model->model, ctx_params);
    if (!ctx) {
        return nullptr;
    }

    bitnet_context* wrapper = new bitnet_context;
    wrapper->ctx = ctx;
    wrapper->model = model->model;
    return wrapper;
}

void bitnet_free_context(bitnet_context* ctx) {
    if (ctx) {
        if (ctx->ctx) {
            llama_free(ctx->ctx);
        }
        delete ctx;
    }
}

// Tokenization
int32_t bitnet_tokenize(bitnet_model* model, const char* text, bitnet_token* tokens, int32_t n_max_tokens, bool add_bos) {
    if (!model || !model->model || !text || !tokens) {
        return -1;
    }

    return llama_tokenize(model->model, text, strlen(text), tokens, n_max_tokens, add_bos, false);
}

const char* bitnet_token_to_piece(bitnet_model* model, bitnet_token token) {
    static thread_local char buffer[256];
    if (!model || !model->model) {
        return "";
    }

    int32_t n = llama_token_to_piece(model->model, token, buffer, sizeof(buffer) - 1, 0, false);
    if (n < 0) {
        return "";
    }
    buffer[n] = '\0';
    return buffer;
}

// Generation
bool bitnet_eval(bitnet_context* ctx, const bitnet_token* tokens, int32_t n_tokens, int32_t n_past) {
    if (!ctx || !ctx->ctx || !tokens || n_tokens <= 0) {
        return false;
    }

    llama_batch batch = llama_batch_init(n_tokens, 0, 1);

    for (int32_t i = 0; i < n_tokens; i++) {
        llama_batch_add(batch, tokens[i], n_past + i, {0}, i == n_tokens - 1);
    }

    int result = llama_decode(ctx->ctx, batch);
    llama_batch_free(batch);

    return result == 0;
}

bitnet_token bitnet_sample(bitnet_context* ctx, bitnet_sampling_params params) {
    if (!ctx || !ctx->ctx) {
        return -1;
    }

    // Get logits
    float* logits = llama_get_logits(ctx->ctx);
    int n_vocab = llama_n_vocab(ctx->model);

    // Create sampler chain
    llama_sampler* sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());

    // Add samplers
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(params.temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(params.top_k));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(params.top_p, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(0));

    // Sample
    llama_token token = llama_sampler_sample(sampler, ctx->ctx, -1);

    llama_sampler_free(sampler);

    return token;
}

// Special tokens
bitnet_token bitnet_token_bos(bitnet_model* model) {
    if (!model || !model->model) {
        return -1;
    }
    return llama_token_bos(model->model);
}

bitnet_token bitnet_token_eos(bitnet_model* model) {
    if (!model || !model->model) {
        return -1;
    }
    return llama_token_eos(model->model);
}

// Model info
int32_t bitnet_n_vocab(bitnet_model* model) {
    if (!model || !model->model) {
        return 0;
    }
    return llama_n_vocab(model->model);
}

int32_t bitnet_n_ctx_train(bitnet_model* model) {
    if (!model || !model->model) {
        return 0;
    }
    return llama_n_ctx_train(model->model);
}
