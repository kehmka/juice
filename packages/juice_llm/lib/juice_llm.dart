/// On-device LLM inference as a Juice bloc — model-acquisition + runtime
/// lifecycle and streaming generation/embedding sessions, behind swappable
/// [LlmProvider] (runtime) and [ModelSource] (weights) seams.
library juice_llm;

export 'src/llm_bloc.dart';
export 'src/llm_config.dart';
export 'src/llm_events.dart';
export 'src/llm_exceptions.dart';
export 'src/llm_model.dart';
export 'src/llm_provider.dart';
export 'src/llm_request.dart';
export 'src/llm_state.dart';
export 'src/model_source.dart';
