//
//  LocalAIAgent-Bridging-Header.h
//  LocalAIAgent
//
//  Bridging header for sherpa-onnx and BitNet C APIs
//

#ifndef LocalAIAgent_Bridging_Header_h
#define LocalAIAgent_Bridging_Header_h

#if !TARGET_OS_MACCATALYST
#import <sherpa-onnx/c-api/c-api.h>
// BitNet integration (WIP)
// #import "LLM/BitNetWrapper.h"
#endif

#endif /* LocalAIAgent_Bridging_Header_h */
