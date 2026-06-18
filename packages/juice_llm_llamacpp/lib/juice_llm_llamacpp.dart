/// Embedded on-device LLM runtime for `juice_llm`: an [LlamaCppProvider] that
/// implements `LlmProvider` by wrapping llama.cpp (GGUF weights, Metal/CPU)
/// through `llama_cpp_dart`. Private, in-process — no server.
library juice_llm_llamacpp;

export 'src/llama_cpp_provider.dart';
