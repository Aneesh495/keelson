#ifndef KEELSON_WREN_VM_H
#define KEELSON_WREN_VM_H

#include <wren.h>
#include <stdint.h>
#include <stddef.h>

typedef struct keelson_vm keelson_vm_t;

// Creates a new Keelson Wren VM runtime environment.
keelson_vm_t *keelson_vm_create(const char *module_root);

// Executes a Wren source string within a module.
int keelson_vm_interpret(keelson_vm_t *vm, const char *module_name, const char *source);

// Executes a Wren source file from disk.
int keelson_vm_run_file(keelson_vm_t *vm, const char *file_path);

// Destroys and cleans up the Wren VM.
void keelson_vm_destroy(keelson_vm_t *vm);

#endif // KEELSON_WREN_VM_H
