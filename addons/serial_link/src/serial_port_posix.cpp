// Implementation POSIX du port serie — Linux et macOS.
//
// Volontairement mince : ouvrir en 115200 8N1 brut, lire sans bloquer, ecrire.
// Toute la logique vit dans link_driver.cpp, qui est testable sans materiel.
#include "serial_port.h"

#if !defined(_WIN32)

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOBSD.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/usb/IOUSBLib.h>
#endif

namespace sslink {
namespace {

class PosixSerialPort : public SerialPort {
  public:
    ~PosixSerialPort() override { close(); }

    bool open(const std::string& path, std::string& err) override {
        close();
        fd_ = ::open(path.c_str(), O_RDWR | O_NOCTTY | O_NONBLOCK);
        if (fd_ < 0) {
            err = std::string("open(") + path + ") : " + std::strerror(errno);
            return false;
        }

        struct termios tio {};
        if (::tcgetattr(fd_, &tio) != 0) {
            err = std::string("tcgetattr : ") + std::strerror(errno);
            close();
            return false;
        }
        ::cfmakeraw(&tio);
        ::cfsetispeed(&tio, B115200);
        ::cfsetospeed(&tio, B115200);
        tio.c_cflag |= (CLOCAL | CREAD);
        tio.c_cflag &= ~static_cast<tcflag_t>(CSTOPB);   // 1 bit de stop
        tio.c_cflag &= ~static_cast<tcflag_t>(PARENB);   // pas de parite
        tio.c_cflag &= ~static_cast<tcflag_t>(CRTSCTS);  // aucun controle de flux
        tio.c_cc[VMIN] = 0;
        tio.c_cc[VTIME] = 0;
        if (::tcsetattr(fd_, TCSANOW, &tio) != 0) {
            err = std::string("tcsetattr : ") + std::strerror(errno);
            close();
            return false;
        }
        ::tcflush(fd_, TCIOFLUSH);
        return true;
    }

    void close() override {
        if (fd_ >= 0) {
            ::close(fd_);
            fd_ = -1;
        }
    }

    bool is_open() const override { return fd_ >= 0; }

    std::size_t read(std::uint8_t* buf, std::size_t n) override {
        if (fd_ < 0) {
            return kReadError;
        }
        const ssize_t r = ::read(fd_, buf, n);
        if (r > 0) {
            return static_cast<std::size_t>(r);
        }
        if (r == 0) {
            // Rien a lire. Sur un pseudo-terminal dont le maitre s'est ferme,
            // c'est aussi ce que rend read() : le raccrochage se manifeste donc
            // par un silence, que le watchdog de link_driver rattrape.
            return 0;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            return 0;
        }
        // EIO, ENXIO, ENODEV : le peripherique a disparu. C'est le cas d'un
        // cable USB arrache, et il doit etre distingue du silence.
        return kReadError;
    }

    bool write(const std::uint8_t* buf, std::size_t n) override {
        if (fd_ < 0) {
            return false;
        }
        std::size_t written = 0;
        while (written < n) {
            const ssize_t w = ::write(fd_, buf + written, n - written);
            if (w > 0) {
                written += static_cast<std::size_t>(w);
                continue;
            }
            if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
                continue;  // les commandes font quelques octets : jamais bloquant en pratique
            }
            return false;
        }
        return true;
    }

  private:
    int fd_ = -1;
};

#if defined(__linux__)

bool read_hex_file(const std::string& path, std::uint16_t& out) {
    std::FILE* f = std::fopen(path.c_str(), "r");
    if (f == nullptr) {
        return false;
    }
    char buf[16] = {0};
    const bool ok = std::fgets(buf, sizeof(buf), f) != nullptr;
    std::fclose(f);
    if (!ok) {
        return false;
    }
    out = static_cast<std::uint16_t>(std::strtoul(buf, nullptr, 16));
    return true;
}

std::string read_text_file(const std::string& path) {
    std::FILE* f = std::fopen(path.c_str(), "r");
    if (f == nullptr) {
        return std::string();
    }
    char buf[256] = {0};
    const char* got = std::fgets(buf, sizeof(buf), f);
    std::fclose(f);
    if (got == nullptr) {
        return std::string();
    }
    std::string s(buf);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) {
        s.pop_back();
    }
    return s;
}

// Remonte l'arborescence sysfs jusqu'au peripherique USB porteur des
// identifiants. Deux a quatre niveaux selon le pilote (cdc_acm, ch341, ftdi).
void fill_usb_ids(const std::string& tty_name, PortInfo& info) {
    std::string dir = "/sys/class/tty/" + tty_name + "/device";
    for (int depth = 0; depth < 5; ++depth) {
        std::uint16_t vid = 0;
        std::uint16_t pid = 0;
        if (read_hex_file(dir + "/idVendor", vid) && read_hex_file(dir + "/idProduct", pid)) {
            info.vid = vid;
            info.pid = pid;
            info.has_ids = true;
            const std::string product = read_text_file(dir + "/product");
            const std::string manufacturer = read_text_file(dir + "/manufacturer");
            if (!product.empty() || !manufacturer.empty()) {
                info.description = manufacturer.empty() ? product : manufacturer + " " + product;
            }
            return;
        }
        dir += "/..";
    }
}

std::vector<PortInfo> enumerate_impl() {
    std::vector<PortInfo> out;
    DIR* d = ::opendir("/sys/class/tty");
    if (d == nullptr) {
        return out;
    }
    while (const dirent* e = ::readdir(d)) {
        const std::string name = e->d_name;
        if (name == "." || name == "..") {
            continue;
        }
        // Un port sans repertoire `device` est un tty virtuel de la console.
        const std::string device_link = "/sys/class/tty/" + name + "/device";
        if (::access(device_link.c_str(), F_OK) != 0) {
            continue;
        }
        PortInfo info;
        info.path = "/dev/" + name;
        if (::access(info.path.c_str(), F_OK) != 0) {
            continue;
        }
        fill_usb_ids(name, info);
        out.push_back(info);
    }
    ::closedir(d);
    std::sort(out.begin(), out.end(),
              [](const PortInfo& a, const PortInfo& b) { return a.path < b.path; });
    return out;
}

#elif defined(__APPLE__)

std::string cf_string_to_std(CFStringRef s) {
    if (s == nullptr) {
        return std::string();
    }
    char buf[512] = {0};
    if (CFStringGetCString(s, buf, sizeof(buf), kCFStringEncodingUTF8)) {
        return std::string(buf);
    }
    return std::string();
}

// Les identifiants USB ne sont pas portes par le service serie lui-meme mais
// par un de ses ancetres dans l'arbre IOKit : on remonte.
bool find_usb_ids(io_object_t service, PortInfo& info) {
    io_object_t node = service;
    IOObjectRetain(node);
    for (int depth = 0; depth < 8; ++depth) {
        CFTypeRef vid = IORegistryEntryCreateCFProperty(node, CFSTR("idVendor"),
                                                        kCFAllocatorDefault, 0);
        CFTypeRef pid = IORegistryEntryCreateCFProperty(node, CFSTR("idProduct"),
                                                        kCFAllocatorDefault, 0);
        if (vid != nullptr && pid != nullptr) {
            int v = 0;
            int p = 0;
            CFNumberGetValue(static_cast<CFNumberRef>(vid), kCFNumberIntType, &v);
            CFNumberGetValue(static_cast<CFNumberRef>(pid), kCFNumberIntType, &p);
            info.vid = static_cast<std::uint16_t>(v);
            info.pid = static_cast<std::uint16_t>(p);
            info.has_ids = true;
            CFRelease(vid);
            CFRelease(pid);
            IOObjectRelease(node);
            return true;
        }
        if (vid != nullptr) {
            CFRelease(vid);
        }
        if (pid != nullptr) {
            CFRelease(pid);
        }
        io_object_t parent = 0;
        if (IORegistryEntryGetParentEntry(node, kIOServicePlane, &parent) != KERN_SUCCESS) {
            IOObjectRelease(node);
            return false;
        }
        IOObjectRelease(node);
        node = parent;
    }
    IOObjectRelease(node);
    return false;
}

std::vector<PortInfo> enumerate_impl() {
    std::vector<PortInfo> out;
    CFMutableDictionaryRef matching = IOServiceMatching(kIOSerialBSDServiceValue);
    if (matching == nullptr) {
        return out;
    }
    CFDictionarySetValue(matching, CFSTR(kIOSerialBSDTypeKey), CFSTR(kIOSerialBSDAllTypes));

    io_iterator_t it = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &it) != KERN_SUCCESS) {
        return out;
    }
    while (io_object_t service = IOIteratorNext(it)) {
        PortInfo info;
        CFTypeRef path = IORegistryEntryCreateCFProperty(service, CFSTR(kIOCalloutDeviceKey),
                                                         kCFAllocatorDefault, 0);
        if (path != nullptr) {
            info.path = cf_string_to_std(static_cast<CFStringRef>(path));
            CFRelease(path);
        }
        CFTypeRef name = IORegistryEntryCreateCFProperty(service, CFSTR(kIOTTYDeviceKey),
                                                         kCFAllocatorDefault, 0);
        if (name != nullptr) {
            info.description = cf_string_to_std(static_cast<CFStringRef>(name));
            CFRelease(name);
        }
        if (!info.path.empty()) {
            find_usb_ids(service, info);
            out.push_back(info);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(it);
    std::sort(out.begin(), out.end(),
              [](const PortInfo& a, const PortInfo& b) { return a.path < b.path; });
    return out;
}

#else

std::vector<PortInfo> enumerate_impl() { return {}; }

#endif

}  // namespace

std::unique_ptr<SerialPort> make_serial_port() {
    return std::unique_ptr<SerialPort>(new PosixSerialPort());
}

std::vector<PortInfo> enumerate_ports() { return enumerate_impl(); }

}  // namespace sslink

#endif  // !_WIN32
