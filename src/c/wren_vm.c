#include "wren_vm.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

struct keelson_vm {
    WrenVM *vm;
    char module_root[256];
};

static void write_fn(WrenVM *vm, const char *text) {
    (void)vm;
    printf("%s", text);
}

static void error_fn(WrenVM *vm, WrenErrorType errorType, const char *module, const int line, const char *msg) {
    (void)vm;
    switch (errorType) {
        case WREN_ERROR_COMPILE:
            fprintf(stderr, "[%s line %d] Compile Error: %s\n", module, line, msg);
            break;
        case WREN_ERROR_STACK_TRACE:
            fprintf(stderr, "[%s line %d] in %s\n", module, line, msg);
            break;
        case WREN_ERROR_RUNTIME:
            fprintf(stderr, "Runtime Error: %s\n", msg);
            break;
    }
}

static void on_load_complete(WrenVM *vm, const char *name, struct WrenLoadModuleResult result) {
    (void)vm;
    (void)name;
    if (result.source) {
        free((void *)result.source);
    }
}

static char *read_file_to_string(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;

    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (len < 0) {
        fclose(f);
        return NULL;
    }

    char *buf = (char *)malloc(len + 1);
    if (!buf) {
        fclose(f);
        return NULL;
    }

    size_t read_bytes = fread(buf, 1, len, f);
    buf[read_bytes] = '\0';
    fclose(f);

    return buf;
}

// Foreign implementations for embedded IO
static void foreign_file_read(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    char *content = read_file_to_string(path);
    if (!content) {
        wrenSetSlotNull(vm, 0);
        return;
    }
    wrenSetSlotString(vm, 0, content);
    free(content);
}

static void foreign_file_exists(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    bool exists = (access(path, F_OK) == 0);
    wrenSetSlotBool(vm, 0, exists);
}

static void foreign_file_delete(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    unlink(path);
    wrenSetSlotNull(vm, 0);
}

static void foreign_file_write_bytes(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    int len = 0;
    const char *bytes = wrenGetSlotBytes(vm, 2, &len);

    FILE *f = fopen(path, "wb");
    if (f) {
        if (len > 0 && bytes) {
            fwrite(bytes, 1, len, f);
        }
        fclose(f);
    }
    wrenSetSlotNull(vm, 0);
}

static void foreign_dir_exists(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    struct stat st;
    bool exists = (stat(path, &st) == 0 && S_ISDIR(st.st_mode));
    wrenSetSlotBool(vm, 0, exists);
}

static void foreign_dir_create(WrenVM *vm) {
    const char *path = wrenGetSlotString(vm, 1);
    mkdir(path, 0755);
    wrenSetSlotNull(vm, 0);
}

static WrenForeignMethodFn bind_foreign_method(WrenVM *vm, const char *module, const char *className, bool isStatic, const char *signature) {
    (void)vm;
    if (strcmp(module, "io") == 0) {
        if (strcmp(className, "File") == 0 && isStatic) {
            if (strcmp(signature, "read(_)") == 0) return foreign_file_read;
            if (strcmp(signature, "exists(_)") == 0) return foreign_file_exists;
            if (strcmp(signature, "delete(_)") == 0) return foreign_file_delete;
            if (strcmp(signature, "writeBytes_(_,_)") == 0) return foreign_file_write_bytes;
        } else if (strcmp(className, "Directory") == 0 && isStatic) {
            if (strcmp(signature, "exists(_)") == 0) return foreign_dir_exists;
            if (strcmp(signature, "create(_)") == 0) return foreign_dir_create;
        }
    }
    return NULL;
}

static const char *s_io_module_source =
"class FileHandle {\n"
"  construct open(path) { _path = path }\n"
"  writeBytes(bytes) { File.writeBytes_(_path, bytes) }\n"
"}\n"
"\n"
"class File {\n"
"  foreign static read(path)\n"
"  foreign static exists(path)\n"
"  foreign static delete(path)\n"
"  foreign static writeBytes_(path, bytes)\n"
"\n"
"  static create(path, block) {\n"
"    var handle = FileHandle.open(path)\n"
"    block.call(handle)\n"
"  }\n"
"}\n"
"\n"
"class Directory {\n"
"  foreign static exists(path)\n"
"  foreign static create(path)\n"
"}\n";

static const char *resolve_module_fn(WrenVM *vm, const char *importer, const char *name) {
    (void)vm;
    (void)importer;
    const char *clean = name;
    while (strncmp(clean, "./", 2) == 0 || strncmp(clean, "../", 3) == 0) {
        if (strncmp(clean, "./", 2) == 0) clean += 2;
        if (strncmp(clean, "../", 3) == 0) clean += 3;
    }
    return strdup(clean);
}

static WrenLoadModuleResult load_module_fn(WrenVM *vm, const char *name) {
    WrenLoadModuleResult result;
    result.source = NULL;
    result.onComplete = on_load_complete;
    result.userData = NULL;

    if (strcmp(name, "io") == 0) {
        result.source = strdup(s_io_module_source);
        return result;
    }

    keelson_vm_t *kvm = (keelson_vm_t *)wrenGetUserData(vm);
    char path[512];

    const char *clean_name = name;
    while (strncmp(clean_name, "./", 2) == 0 || strncmp(clean_name, "../", 3) == 0) {
        if (strncmp(clean_name, "./", 2) == 0) clean_name += 2;
        if (strncmp(clean_name, "../", 3) == 0) clean_name += 3;
    }

    const char *prefixes[] = {
        "",
        kvm ? kvm->module_root : "src/wren",
        "src/wren",
        "src/wren/core",
        "src/wren/storage",
        "src/wren/workflows",
        "test",
        "test/unit",
        "test/saga",
        "test/replay",
        "test/integration",
        "examples",
        NULL
    };

    for (int i = 0; prefixes[i] != NULL; i++) {
        if (strlen(prefixes[i]) > 0) {
            snprintf(path, sizeof(path), "%s/%s.wren", prefixes[i], clean_name);
        } else {
            snprintf(path, sizeof(path), "%s.wren", clean_name);
        }

        char *src = read_file_to_string(path);
        if (src) {
            result.source = src;
            return result;
        }
    }

    return result;
}

keelson_vm_t *keelson_vm_create(const char *module_root) {
    keelson_vm_t *kvm = (keelson_vm_t *)malloc(sizeof(keelson_vm_t));
    if (!kvm) return NULL;

    memset(kvm, 0, sizeof(keelson_vm_t));
    if (module_root) {
        strncpy(kvm->module_root, module_root, sizeof(kvm->module_root) - 1);
    } else {
        strcpy(kvm->module_root, "src/wren");
    }

    WrenConfiguration config;
    wrenInitConfiguration(&config);
    config.writeFn = write_fn;
    config.errorFn = error_fn;
    config.resolveModuleFn = resolve_module_fn;
    config.loadModuleFn = load_module_fn;
    config.bindForeignMethodFn = bind_foreign_method;
    config.userData = kvm;

    kvm->vm = wrenNewVM(&config);
    if (!kvm->vm) {
        free(kvm);
        return NULL;
    }

    return kvm;
}

int keelson_vm_interpret(keelson_vm_t *kvm, const char *module_name, const char *source) {
    if (!kvm || !kvm->vm) return -1;
    WrenInterpretResult res = wrenInterpret(kvm->vm, module_name, source);
    return (res == WREN_RESULT_SUCCESS) ? 0 : 1;
}

int keelson_vm_run_file(keelson_vm_t *kvm, const char *file_path) {
    if (!kvm || !kvm->vm) return -1;

    char *source = read_file_to_string(file_path);
    if (!source) {
        fprintf(stderr, "Error: Could not open Wren file: %s\n", file_path);
        return -2;
    }

    int rc = keelson_vm_interpret(kvm, file_path, source);
    free(source);
    return rc;
}

void keelson_vm_destroy(keelson_vm_t *kvm) {
    if (!kvm) return;
    if (kvm->vm) {
        wrenFreeVM(kvm->vm);
        kvm->vm = NULL;
    }
    free(kvm);
}
