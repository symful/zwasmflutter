// Placeholder translation unit. The runtime and the C-ABI shim both live in
// src/zwasm/ and are linked into this shared library as a whole archive.
#if defined(_WIN32)
__declspec(dllexport) int zwasm_plugin_anchor(void) { return 0; }
#else
__attribute__((visibility("default"))) int zwasm_plugin_anchor(void) { return 0; }
#endif
