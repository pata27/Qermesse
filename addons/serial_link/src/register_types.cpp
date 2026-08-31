#include <gdextension_interface.h>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "serial_link.h"

using namespace godot;

void initialize_serial_link(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    GDREGISTER_CLASS(SerialLink);
}

void uninitialize_serial_link(ModuleInitializationLevel level) {
    if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT serial_link_library_init(GDExtensionInterfaceGetProcAddress get_proc,
                                                    GDExtensionClassLibraryPtr library,
                                                    GDExtensionInitialization* init) {
    GDExtensionBinding::InitObject obj(get_proc, library, init);
    obj.register_initializer(initialize_serial_link);
    obj.register_terminator(uninitialize_serial_link);
    obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return obj.init();
}
}
