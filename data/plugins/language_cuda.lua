-- mod-version:3
--
-- CUDA C++ syntax highlighting.
--
-- Derived from language_cpp, with the CUDA additions:
--   * execution space / memory space qualifiers (__global__, __device__, ...)
--   * built-in kernel variables (threadIdx, blockIdx, ...)
--   * vector, half and bfloat16 types (float4, __half, __nv_bfloat16, ...)
--   * warp / block intrinsics (__syncthreads, __shfl_sync, ...)
--   * cudaXxx runtime API types and enum constants
--   * the <<<...>>> kernel launch configuration delimiters
--
-- .cu was removed from language_cpp's file list when this plugin was added, so
-- the two do not compete and load order does not matter.
local syntax = require "core.syntax"

-- integer suffix combinations as a regex
local isuf = [[(?:[lL][uU]|ll[uU]|LL[uU]|[uU][lL]\b|[uU]ll|[uU]LL|[uU]|[lL]\b|ll|LL)?]]
-- float suffix combinations as a Lua pattern / regex
local fsuf = "[fFlL]?"
-- number with digit separator as a regex non-capturing group
local digitsep = [[(?:\d[\d']*)]]

syntax.add {
  name = "CUDA",
  files = { "%.cu$", "%.cuh$" },
  comment = "//",
  block_comment = { "/*", "*/" },
  symbol_pattern = "[%a_#][%w_]*",
  symbol_non_word_chars = " \t\n/\\()\"':,.;<>~!@$%^&*|+=[]{}`?-",
  patterns = {
    { pattern = "//.*",                                                            type = "comment"  },
    { pattern = { "/%*", "%*/" },                                                  type = "comment"  },
    { pattern = { '"', '"', '\\' },                                                type = "string"   },
    { pattern = { "'", "'", '\\' },                                                type = "string"   },
    -- kernel launch configuration, before the generic operator rules so the
    -- triple angle brackets stay a single token
    { pattern = "[%a_][%w_]*()%s*<<<",                                             type = { "function", "operator" } },
    { pattern = "<<<",                                                             type = "operator" },
    { pattern = ">>>",                                                             type = "operator" },
    { regex   = "0x[0-9a-fA-F][0-9a-fA-F']*"..isuf,                                type = "number"   },
    { regex   = "0b[01][01']*"..isuf,                                              type = "number"   },
    { regex   = "0()[0-7][0-7']*"..isuf,                                           type = { "keyword", "number" } },
    { regex   = digitsep.."\\.?"..digitsep.."?(?:[Ee][-+]?"..digitsep..")?"..fsuf, type = "number" },
    { regex   = "\\."..digitsep.."(?:[Ee][-+]?"..digitsep..")?"..fsuf,             type = "number" },
    { pattern = "[%+%-=/%*%^%%<>!~|:&]",                                           type = "operator" },
    { pattern = "##",                                                              type = "operator" },
    { pattern = "struct%s()[%a_][%w_]*",                                           type = {"keyword", "keyword2"} },
    { pattern = "class%s()[%a_][%w_]*",                                            type = {"keyword", "keyword2"} },
    { pattern = "enum%s()[%a_][%w_]*",                                             type = {"keyword", "keyword2"} },
    { pattern = "union%s()[%a_][%w_]*",                                            type = {"keyword", "keyword2"} },
    { pattern = "namespace%s()[%a_][%w_]*",                                        type = {"keyword", "keyword2"} },
    -- static declarations
    { pattern = "static()%s+()inline",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()constexpr",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()constinit",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()consteval",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()const",
      type = { "keyword", "normal", "keyword" }
    },
    { pattern = "static()%s+()[%a_][%w_]*",
      type = { "keyword", "normal", "literal" }
    },
    -- match method type declarations
    { pattern = "[%a_][%w_]*()%s*()%**()%s*()[%a_][%w_]*()%s*()::",
      type = {
        "literal", "normal", "operator", "normal",
        "literal", "normal", "operator"
      }
    },
    -- match single line type declarations (exclude keywords)
    { pattern = "^%s*_?%u[%u_][%u%d_]*%s*\n", -- skip uppercase constants
      type = "number"
    },
    { pattern = "^%s*()[%a_][%w_]*()%s*&()%s*\n", -- reference
      type = { "normal", "literal", "operator", "normal" }
    },
    { pattern = "^%s*()[%a_][%w_]*()%s*%*+()%s*\n", -- pointer
      type = { "normal", "literal", "operator", "normal" }
    },
    { pattern = "^%s*()[%a_][%w_]*()%s*\n", -- non-pointer
      type = { "normal", "literal", "normal" }
    },
    -- match function type declarations
    { pattern = "[%a_][%w_]*()%*+()%s+()[%a_][%w_]*()%s*%f[%(]",
      type = { "literal", "operator", "normal", "function", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()%*+()[%a_][%w_]*()%s*%f[%(]",
      type = { "literal", "normal", "operator", "function", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*()%s*%f[%(]",
      type = { "literal", "normal", "function", "normal" }
    },
    -- match generic variable type declarations (eg: vector<int> myvector)
    { regex = "^\\s*[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s*[\\*&]*\\s*\n))",
      type = "literal"
    },
    { regex = "[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s*\\*+\\s+[\\p{L}_][\\p{L}\\d_]*))",
      type = "literal"
    },
    { regex = "[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s*&\\s+[\\p{L}_][\\p{L}\\d_]*))",
      type = "literal"
    },
    { regex = "[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s+\\*+\\s*[\\p{L}_][\\p{L}\\d_]*))",
      type = "literal"
    },
    { regex = "[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s+&\\s*[\\p{L}_][\\p{L}\\d_]*))",
      type = "literal"
    },
    { regex = "[\\p{L}_][\\p{L}\\d_]*(?=(?:<.*>\\s+[\\p{L}_][\\p{L}\\d_]*))",
      type = "literal"
    },
    -- match variable type declarations
    { pattern = "[%a_][%w_]*()%*+()%s+()[%a_][%w_]*",
      type = { "literal", "operator", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()%*+()[%a_][%w_]*",
      type = { "literal", "normal", "operator", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*()%s*()[;,%[%)]",
      type = { "literal", "normal", "normal", "normal", "normal" }
    },
    { pattern = "^%s*()[%a_][%w_]*()%s+[%a_][%w_]*()%s*\n",
      type = { "normal", "literal", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()[%a_][%w_]*()%s*()=",
      type = { "literal", "normal", "normal", "normal", "operator" }
    },
    { pattern = "[%a_][%w_]*()&()%s+()[%a_][%w_]*",
      type = { "literal", "operator", "normal", "normal" }
    },
    { pattern = "[%a_][%w_]*()%s+()&()[%a_][%w_]*",
      type = { "literal", "normal", "operator", "normal" }
    },
    -- Match scope operator element access
    { pattern = "[%a_][%w_]*()%s*()::",
      type = { "literal", "normal", "operator" }
    },
    -- Uppercase constants of at least 2 chars in len
    { pattern = "_?%u[%u_][%u%d_]*%s*%f[%(]", -- when used as function
      type = "number"
    },
    { pattern = "_?%u[%u_][%u%d_]*%f[%s%+%*%-%.%)%]}%?%^%%=/<>~|&;:,!]",
      type = "number"
    },
    -- Magic constants
    { pattern = "__[%u%l]+__",              type = "number"   },
    -- all other functions
    { pattern = "[%a_][%w_]*()%s*%f[(]",    type = {"function", "normal"} },
    -- Macros
    { pattern = "^%s*#%s*define%s+()[%a_][%a%d_]*",
      type = { "keyword", "symbol" }
    },
    { pattern = "#%s*include%s+()<.->",
      type = { "keyword", "string" }
    },
    { pattern = "%f[#]#%s*[%a_][%w_]*",     type = "keyword"   },
    -- Everything else to make the tokenizer work properly
    { pattern = "[%a_][%w_]*",              type = "symbol"   },
  },
  symbols = {
    -- ------------------------------------------------------------------
    -- CUDA: execution space and memory space qualifiers
    -- ------------------------------------------------------------------
    ["__global__"]        = "keyword",
    ["__device__"]        = "keyword",
    ["__host__"]          = "keyword",
    ["__shared__"]        = "keyword",
    ["__constant__"]      = "keyword",
    ["__managed__"]       = "keyword",
    ["__grid_constant__"] = "keyword",
    ["__restrict__"]      = "keyword",
    ["__forceinline__"]   = "keyword",
    ["__noinline__"]      = "keyword",
    ["__inline_hint__"]   = "keyword",
    ["__launch_bounds__"] = "keyword",
    ["__align__"]         = "keyword",
    ["__cluster_dims__"]  = "keyword",
    ["__nv_exec_check_disable__"] = "keyword",

    -- ------------------------------------------------------------------
    -- CUDA: built-in kernel variables
    -- ------------------------------------------------------------------
    ["threadIdx"] = "literal",
    ["blockIdx"]  = "literal",
    ["blockDim"]  = "literal",
    ["gridDim"]   = "literal",
    ["warpSize"]  = "literal",

    -- ------------------------------------------------------------------
    -- CUDA: types
    -- ------------------------------------------------------------------
    ["dim3"]                = "keyword2",
    ["cudaStream_t"]        = "keyword2",
    ["cudaEvent_t"]         = "keyword2",
    ["cudaError_t"]         = "keyword2",
    ["cudaGraph_t"]         = "keyword2",
    ["cudaGraphExec_t"]     = "keyword2",
    ["cudaDeviceProp"]      = "keyword2",
    ["cudaFuncAttributes"]  = "keyword2",
    ["cudaMemcpyKind"]      = "keyword2",
    ["cudaTextureObject_t"] = "keyword2",
    ["cudaSurfaceObject_t"] = "keyword2",
    -- half / bfloat16 / fp8
    ["half"]            = "keyword2",
    ["half2"]           = "keyword2",
    ["__half"]          = "keyword2",
    ["__half2"]         = "keyword2",
    ["__half_raw"]      = "keyword2",
    ["__nv_bfloat16"]   = "keyword2",
    ["__nv_bfloat162"]  = "keyword2",
    ["nv_bfloat16"]     = "keyword2",
    ["nv_bfloat162"]    = "keyword2",
    ["__nv_fp8_e4m3"]   = "keyword2",
    ["__nv_fp8_e5m2"]   = "keyword2",
    ["__nv_fp8x2_e4m3"] = "keyword2",
    ["__nv_fp8x2_e5m2"] = "keyword2",
    ["__nv_fp8x4_e4m3"] = "keyword2",
    ["__nv_fp8x4_e5m2"] = "keyword2",
    -- vector types
    ["char1"] = "keyword2", ["char2"] = "keyword2", ["char3"] = "keyword2", ["char4"] = "keyword2",
    ["uchar1"] = "keyword2", ["uchar2"] = "keyword2", ["uchar3"] = "keyword2", ["uchar4"] = "keyword2",
    ["short1"] = "keyword2", ["short2"] = "keyword2", ["short3"] = "keyword2", ["short4"] = "keyword2",
    ["ushort1"] = "keyword2", ["ushort2"] = "keyword2", ["ushort3"] = "keyword2", ["ushort4"] = "keyword2",
    ["int1"] = "keyword2", ["int2"] = "keyword2", ["int3"] = "keyword2", ["int4"] = "keyword2",
    ["uint1"] = "keyword2", ["uint2"] = "keyword2", ["uint3"] = "keyword2", ["uint4"] = "keyword2",
    ["long1"] = "keyword2", ["long2"] = "keyword2", ["long3"] = "keyword2", ["long4"] = "keyword2",
    ["ulong1"] = "keyword2", ["ulong2"] = "keyword2", ["ulong3"] = "keyword2", ["ulong4"] = "keyword2",
    ["longlong1"] = "keyword2", ["longlong2"] = "keyword2",
    ["ulonglong1"] = "keyword2", ["ulonglong2"] = "keyword2",
    ["float1"] = "keyword2", ["float2"] = "keyword2", ["float3"] = "keyword2", ["float4"] = "keyword2",
    ["double1"] = "keyword2", ["double2"] = "keyword2", ["double3"] = "keyword2", ["double4"] = "keyword2",

    -- ------------------------------------------------------------------
    -- CUDA: commonly used runtime enum constants
    -- ------------------------------------------------------------------
    ["cudaSuccess"]              = "literal",
    ["cudaStreamDefault"]        = "literal",
    ["cudaStreamNonBlocking"]    = "literal",
    ["cudaStreamPerThread"]      = "literal",
    ["cudaStreamLegacy"]         = "literal",
    ["cudaEventDefault"]         = "literal",
    ["cudaEventBlockingSync"]    = "literal",
    ["cudaEventDisableTiming"]   = "literal",
    ["cudaMemcpyHostToHost"]     = "literal",
    ["cudaMemcpyHostToDevice"]   = "literal",
    ["cudaMemcpyDeviceToHost"]   = "literal",
    ["cudaMemcpyDeviceToDevice"] = "literal",
    ["cudaMemcpyDefault"]        = "literal",
    ["cudaHostAllocDefault"]     = "literal",
    ["cudaHostAllocPortable"]    = "literal",
    ["cudaHostAllocMapped"]      = "literal",
    ["cudaHostAllocWriteCombined"] = "literal",
    ["cudaHostRegisterDefault"]  = "literal",
    ["cudaHostRegisterPortable"] = "literal",
    ["cudaHostRegisterMapped"]   = "literal",
    ["cudaSharedMemBankSizeEightByte"] = "literal",
    ["cudaFuncAttributeMaxDynamicSharedMemorySize"] = "literal",
    ["cudaFuncAttributePreferredSharedMemoryCarveout"] = "literal",

    -- ------------------------------------------------------------------
    -- CUDA: synchronization / warp / fence intrinsics
    -- ------------------------------------------------------------------
    ["__syncthreads"]        = "keyword",
    ["__syncthreads_count"]  = "keyword",
    ["__syncthreads_and"]    = "keyword",
    ["__syncthreads_or"]     = "keyword",
    ["__syncwarp"]           = "keyword",
    ["__threadfence"]        = "keyword",
    ["__threadfence_block"]  = "keyword",
    ["__threadfence_system"] = "keyword",
    ["__activemask"]         = "keyword",
    ["__ballot_sync"]        = "keyword",
    ["__all_sync"]           = "keyword",
    ["__any_sync"]           = "keyword",
    ["__uni_sync"]           = "keyword",
    ["__match_any_sync"]     = "keyword",
    ["__match_all_sync"]     = "keyword",
    ["__shfl_sync"]          = "keyword",
    ["__shfl_up_sync"]       = "keyword",
    ["__shfl_down_sync"]     = "keyword",
    ["__shfl_xor_sync"]      = "keyword",
    ["__trap"]               = "keyword",
    ["__brkpt"]              = "keyword",

    -- ------------------------------------------------------------------
    -- C / C++ keywords (same set as the bundled C++ plugin)
    -- ------------------------------------------------------------------
    ["alignof"]   = "keyword",
    ["alignas"]   = "keyword",
    ["and"]       = "keyword",
    ["and_eq"]    = "keyword",
    ["not"]       = "keyword",
    ["not_eq"]    = "keyword",
    ["or"]        = "keyword",
    ["or_eq"]     = "keyword",
    ["xor"]       = "keyword",
    ["xor_eq"]    = "keyword",
    ["private"]   = "keyword",
    ["protected"] = "keyword",
    ["public"]    = "keyword",
    ["register"]  = "keyword",
    ["nullptr"]   = "keyword",
    ["operator"]  = "keyword",
    ["asm"]       = "keyword",
    ["bitand"]    = "keyword",
    ["bitor"]     = "keyword",
    ["catch"]     = "keyword",
    ["throw"]     = "keyword",
    ["try"]       = "keyword",
    ["class"]     = "keyword",
    ["compl"]     = "keyword",
    ["explicit"]  = "keyword",
    ["export"]    = "keyword",
    ["concept"]   = "keyword",
    ["consteval"] = "keyword",
    ["constexpr"] = "keyword",
    ["constinit"] = "keyword",
    ["const_cast"] = "keyword",
    ["dynamic_cast"] = "keyword",
    ["reinterpret_cast"] = "keyword",
    ["static_cast"]   = "keyword",
    ["static_assert"] = "keyword",
    ["template"]  = "keyword",
    ["this"]      = "keyword",
    ["thread_local"] = "keyword",
    ["requires"]  = "keyword",
    ["co_await"]  = "keyword",
    ["co_return"] = "keyword",
    ["co_yield"]  = "keyword",
    ["decltype"]  = "keyword",
    ["delete"]    = "keyword",
    ["friend"]    = "keyword",
    ["typeid"]    = "keyword",
    ["typename"]  = "keyword",
    ["mutable"]   = "keyword",
    ["override"]  = "keyword",
    ["virtual"]   = "keyword",
    ["using"]     = "keyword",
    ["namespace"] = "keyword",
    ["new"]       = "keyword",
    ["noexcept"]  = "keyword",
    ["if"]        = "keyword",
    ["then"]      = "keyword",
    ["else"]      = "keyword",
    ["elseif"]    = "keyword",
    ["do"]        = "keyword",
    ["while"]     = "keyword",
    ["for"]       = "keyword",
    ["break"]     = "keyword",
    ["continue"]  = "keyword",
    ["return"]    = "keyword",
    ["goto"]      = "keyword",
    ["struct"]    = "keyword",
    ["union"]     = "keyword",
    ["typedef"]   = "keyword",
    ["enum"]      = "keyword",
    ["extern"]    = "keyword",
    ["static"]    = "keyword",
    ["volatile"]  = "keyword",
    ["const"]     = "keyword",
    ["inline"]    = "keyword",
    ["switch"]    = "keyword",
    ["case"]      = "keyword",
    ["default"]   = "keyword",
    ["auto"]      = "keyword",
    ["void"]      = "keyword2",
    ["int"]       = "keyword2",
    ["short"]     = "keyword2",
    ["long"]      = "keyword2",
    ["float"]     = "keyword2",
    ["double"]    = "keyword2",
    ["char"]      = "keyword2",
    ["signed"]    = "keyword2",
    ["unsigned"]  = "keyword2",
    ["bool"]      = "keyword2",
    ["true"]      = "literal",
    ["false"]     = "literal",
    ["NULL"]      = "literal",
    ["wchar_t"]   = "keyword2",
    ["char8_t"]   = "keyword2",
    ["char16_t"]  = "keyword2",
    ["char32_t"]  = "keyword2",
    ["#include"]  = "keyword",
    ["#if"]       = "keyword",
    ["#ifdef"]    = "keyword",
    ["#ifndef"]   = "keyword",
    ["#elif"]     = "keyword",
    ["#else"]     = "keyword",
    ["#elseif"]   = "keyword",
    ["#endif"]    = "keyword",
    ["#define"]   = "keyword",
    ["#undef"]    = "keyword",
    ["#warning"]  = "keyword",
    ["#error"]    = "keyword",
    ["#pragma"]   = "keyword",
  },
}
