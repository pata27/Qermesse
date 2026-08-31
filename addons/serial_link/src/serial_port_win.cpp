// Implementation Windows du port serie.
//
// Meme mince couche que la version POSIX : ouvrir en 115200 8N1, lire sans
// bloquer, ecrire. Aucune logique — elle vit dans link_driver.cpp.
#include "serial_port.h"

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
// L'ordre compte : initguid.h AVANT devguid.h, faute de quoi GUID_DEVCLASS_PORTS
// est declare sans etre defini dans cette unite de compilation. setupapi.h doit
// suivre windows.h.
#include <initguid.h>
#include <devguid.h>
#include <setupapi.h>

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <string>

// SetupAPI pour l'enumeration, advapi32 pour la cle de registre qui porte le
// nom du port (COM3). CMake lie advapi32 par defaut, SCons non : sans ce
// pragma, la CI Windows echoue au LIEN et pas a la compilation, ce qui rend le
// diagnostic bien moins evident.
#pragma comment(lib, "setupapi.lib")
#pragma comment(lib, "advapi32.lib")

namespace sslink {
namespace {

std::string last_error_text() {
    const DWORD code = ::GetLastError();
    char buf[256] = {0};
    ::FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr, code,
                     0, buf, sizeof(buf) - 1, nullptr);
    std::string s(buf);
    while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) {
        s.pop_back();
    }
    return s.empty() ? ("erreur " + std::to_string(code)) : s;
}

class WindowsSerialPort : public SerialPort {
  public:
    ~WindowsSerialPort() override { close(); }

    bool open(const std::string& path, std::string& err) override {
        close();
        // Au-dela de COM9 la forme courte ne suffit plus : il faut le prefixe
        // \\\\.\\ — piege classique, et le boitier atterrit souvent sur COM11.
        std::string full = path;
        if (full.rfind("\\\\.\\", 0) != 0) {
            full = "\\\\.\\" + path;
        }
        handle_ = ::CreateFileA(full.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                                OPEN_EXISTING, 0, nullptr);
        if (handle_ == INVALID_HANDLE_VALUE) {
            handle_ = nullptr;
            err = "CreateFile(" + path + ") : " + last_error_text();
            return false;
        }

        DCB dcb = {};
        dcb.DCBlength = sizeof(dcb);
        if (!::GetCommState(handle_, &dcb)) {
            err = "GetCommState : " + last_error_text();
            close();
            return false;
        }
        dcb.BaudRate = CBR_115200;
        dcb.ByteSize = 8;
        dcb.Parity = NOPARITY;
        dcb.StopBits = ONESTOPBIT;
        dcb.fBinary = TRUE;
        dcb.fParity = FALSE;
        dcb.fOutxCtsFlow = FALSE;
        dcb.fOutxDsrFlow = FALSE;
        dcb.fDtrControl = DTR_CONTROL_ENABLE;
        dcb.fRtsControl = RTS_CONTROL_ENABLE;
        dcb.fOutX = FALSE;
        dcb.fInX = FALSE;
        if (!::SetCommState(handle_, &dcb)) {
            err = "SetCommState : " + last_error_text();
            close();
            return false;
        }

        // Lecture strictement non bloquante : ReadFile rend immediatement ce
        // qui est disponible, meme rien.
        COMMTIMEOUTS timeouts = {};
        timeouts.ReadIntervalTimeout = MAXDWORD;
        timeouts.ReadTotalTimeoutConstant = 0;
        timeouts.ReadTotalTimeoutMultiplier = 0;
        timeouts.WriteTotalTimeoutConstant = 500;
        timeouts.WriteTotalTimeoutMultiplier = 0;
        if (!::SetCommTimeouts(handle_, &timeouts)) {
            err = "SetCommTimeouts : " + last_error_text();
            close();
            return false;
        }
        ::PurgeComm(handle_, PURGE_RXCLEAR | PURGE_TXCLEAR);
        return true;
    }

    void close() override {
        if (handle_ != nullptr) {
            ::CloseHandle(handle_);
            handle_ = nullptr;
        }
    }

    bool is_open() const override { return handle_ != nullptr; }

    std::size_t read(std::uint8_t* buf, std::size_t n) override {
        if (handle_ == nullptr) {
            return kReadError;
        }
        DWORD got = 0;
        if (!::ReadFile(handle_, buf, static_cast<DWORD>(n), &got, nullptr)) {
            // Le peripherique a disparu — cable arrache.
            return kReadError;
        }
        return static_cast<std::size_t>(got);
    }

    bool write(const std::uint8_t* buf, std::size_t n) override {
        if (handle_ == nullptr) {
            return false;
        }
        DWORD written = 0;
        if (!::WriteFile(handle_, buf, static_cast<DWORD>(n), &written, nullptr)) {
            return false;
        }
        return written == n;
    }

  private:
    HANDLE handle_ = nullptr;
};

// Extrait VID et PID d'un identifiant materiel de la forme
// "USB\VID_2341&PID_0043&REV_0001".
bool parse_hardware_id(const std::string& id, std::uint16_t& vid, std::uint16_t& pid) {
    const std::size_t v = id.find("VID_");
    const std::size_t p = id.find("PID_");
    if (v == std::string::npos || p == std::string::npos) {
        return false;
    }
    if (v + 8 > id.size() || p + 8 > id.size()) {
        return false;
    }
    vid = static_cast<std::uint16_t>(std::strtoul(id.substr(v + 4, 4).c_str(), nullptr, 16));
    pid = static_cast<std::uint16_t>(std::strtoul(id.substr(p + 4, 4).c_str(), nullptr, 16));
    return true;
}

}  // namespace

std::unique_ptr<SerialPort> make_serial_port() {
    return std::unique_ptr<SerialPort>(new WindowsSerialPort());
}

std::vector<PortInfo> enumerate_ports() {
    std::vector<PortInfo> out;

    const GUID ports_class = GUID_DEVCLASS_PORTS;
    HDEVINFO set = ::SetupDiGetClassDevsA(&ports_class, nullptr, nullptr, DIGCF_PRESENT);
    if (set == INVALID_HANDLE_VALUE) {
        return out;
    }

    SP_DEVINFO_DATA data = {};
    data.cbSize = sizeof(data);
    for (DWORD i = 0; ::SetupDiEnumDeviceInfo(set, i, &data); ++i) {
        // Nom du port (COM3) : il vit dans la cle de registre du peripherique.
        HKEY key = ::SetupDiOpenDevRegKey(set, &data, DICS_FLAG_GLOBAL, 0, DIREG_DEV, KEY_READ);
        if (key == INVALID_HANDLE_VALUE) {
            continue;
        }
        char port_name[64] = {0};
        DWORD size = sizeof(port_name);
        DWORD type = 0;
        const LONG got = ::RegQueryValueExA(key, "PortName", nullptr, &type,
                                            reinterpret_cast<LPBYTE>(port_name), &size);
        ::RegCloseKey(key);
        if (got != ERROR_SUCCESS || type != REG_SZ) {
            continue;
        }

        PortInfo info;
        info.path = port_name;

        char friendly[256] = {0};
        if (::SetupDiGetDeviceRegistryPropertyA(set, &data, SPDRP_FRIENDLYNAME, nullptr,
                                                reinterpret_cast<PBYTE>(friendly),
                                                sizeof(friendly), nullptr)) {
            info.description = friendly;
        }

        char hardware_id[512] = {0};
        if (::SetupDiGetDeviceRegistryPropertyA(set, &data, SPDRP_HARDWAREID, nullptr,
                                                reinterpret_cast<PBYTE>(hardware_id),
                                                sizeof(hardware_id), nullptr)) {
            std::uint16_t vid = 0;
            std::uint16_t pid = 0;
            if (parse_hardware_id(hardware_id, vid, pid)) {
                info.vid = vid;
                info.pid = pid;
                info.has_ids = true;
            }
        }
        out.push_back(info);
    }
    ::SetupDiDestroyDeviceInfoList(set);

    std::sort(out.begin(), out.end(),
              [](const PortInfo& a, const PortInfo& b) { return a.path < b.path; });
    return out;
}

}  // namespace sslink

#endif  // _WIN32
