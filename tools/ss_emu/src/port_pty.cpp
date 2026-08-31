#include "port_pty.h"

#if defined(_WIN32)

namespace ssemu {
PtyPort::~PtyPort() = default;
bool PtyPort::open(std::string& err) {
    err = "le frontal pseudo-terminal est POSIX ; sous Windows, utiliser --stdio "
          "(docs/07 §3)";
    return false;
}
void PtyPort::close() {}
bool PtyPort::reopen(std::string& err) { return open(err); }
bool PtyPort::set_link(const std::string&, std::string& err) { return open(err); }
bool PtyPort::create_pty(std::string& err) { return open(err); }
bool PtyPort::refresh_link(std::string& err) { return open(err); }
std::size_t PtyPort::read_available(std::uint8_t*, std::size_t) { return 0; }
void PtyPort::pump_tx(double) {}
}  // namespace ssemu

#else

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <cstring>
#include <termios.h>
#include <unistd.h>

#include <algorithm>

namespace ssemu {
namespace {

constexpr double kBytesPerMs = 115200.0 / 10.0 / 1000.0;  // 8N1 : 10 bits par octet

std::string errno_text(const char* what) {
    return std::string(what) + " : " + std::strerror(errno);
}

}  // namespace

PtyPort::~PtyPort() { close(); }

bool PtyPort::create_pty(std::string& err) {
    master_fd_ = ::posix_openpt(O_RDWR | O_NOCTTY);
    if (master_fd_ < 0) {
        err = errno_text("posix_openpt");
        return false;
    }
    if (::grantpt(master_fd_) != 0) {
        err = errno_text("grantpt");
        return false;
    }
    if (::unlockpt(master_fd_) != 0) {
        err = errno_text("unlockpt");
        return false;
    }
    const char* name = ::ptsname(master_fd_);
    if (name == nullptr) {
        err = errno_text("ptsname");
        return false;
    }
    device_ = name;

    // On garde l'esclave ouvert : sinon, dès que le client referme le port, un
    // read() sur le maître renvoie EIO et l'émulateur croit à une panne.
    slave_fd_ = ::open(device_.c_str(), O_RDWR | O_NOCTTY);
    if (slave_fd_ < 0) {
        err = errno_text("open(slave)");
        return false;
    }

    // Mode brut : ni écho, ni traduction \n -> \r\n. Sans cela, la discipline
    // de ligne réécrirait les trames et le protocole serait faussé.
    //
    // La configuration s'applique sur l'ESCLAVE, pas sur le maître. Linux
    // tolère tcgetattr sur le maître, macOS non : il répond ENOTTY,
    // « Inappropriate ioctl for device ». C'est l'esclave qui porte la
    // discipline de ligne, donc c'est lui qu'il faut configurer — et cela
    // fonctionne sur les deux systèmes.
    struct termios tio {};
    if (::tcgetattr(slave_fd_, &tio) != 0) {
        err = errno_text("tcgetattr");
        return false;
    }
    ::cfmakeraw(&tio);
    ::cfsetispeed(&tio, B115200);
    ::cfsetospeed(&tio, B115200);
    if (::tcsetattr(slave_fd_, TCSANOW, &tio) != 0) {
        err = errno_text("tcsetattr");
        return false;
    }

    const int flags = ::fcntl(master_fd_, F_GETFL, 0);
    if (flags < 0 || ::fcntl(master_fd_, F_SETFL, flags | O_NONBLOCK) != 0) {
        err = errno_text("fcntl(O_NONBLOCK)");
        return false;
    }
    return true;
}

bool PtyPort::open(std::string& err) {
    if (is_open()) {
        return true;
    }
    if (!create_pty(err)) {
        close();
        return false;
    }
    if (!link_.empty() && !refresh_link(err)) {
        close();
        return false;
    }
    return true;
}

void PtyPort::close() {
    if (slave_fd_ >= 0) {
        ::close(slave_fd_);
        slave_fd_ = -1;
    }
    if (master_fd_ >= 0) {
        ::close(master_fd_);
        master_fd_ = -1;
    }
    device_.clear();
    outbox_.clear();
    credit_bytes_ = 0.0;
    last_pump_ms_ = -1.0;
}

bool PtyPort::reopen(std::string& err) {
    close();
    return open(err);
}

bool PtyPort::refresh_link(std::string& err) {
    ::unlink(link_.c_str());
    if (::symlink(device_.c_str(), link_.c_str()) != 0) {
        err = errno_text(("symlink " + link_).c_str());
        return false;
    }
    return true;
}

bool PtyPort::set_link(const std::string& path, std::string& err) {
    link_ = path;
    if (!is_open()) {
        return true;
    }
    return refresh_link(err);
}

std::size_t PtyPort::read_available(std::uint8_t* buf, std::size_t n) {
    if (!is_open() || n == 0) {
        return 0;
    }
    const ssize_t r = ::read(master_fd_, buf, n);
    if (r <= 0) {
        return 0;  // EAGAIN quand rien n'est disponible
    }
    return std::size_t(r);
}

void PtyPort::pump_tx(double now_ms) {
    if (!is_open()) {
        // Ligne coupée : les octets émis par le firmware partent dans le vide,
        // comme sur un Arduino dont le câble vient d'être arraché.
        dropped_ += outbox_.size();
        outbox_.clear();
        return;
    }
    if (last_pump_ms_ < 0.0) {
        last_pump_ms_ = now_ms;
    }
    const double dt = now_ms - last_pump_ms_;
    last_pump_ms_ = now_ms;

    std::size_t budget = outbox_.size();
    if (baud_pacing_) {
        credit_bytes_ += dt * kBytesPerMs;
        credit_bytes_ = std::min(credit_bytes_, 4096.0);
        budget = std::min(outbox_.size(), std::size_t(credit_bytes_ < 0.0 ? 0.0 : credit_bytes_));
    }
    if (budget == 0) {
        return;
    }
    const ssize_t w = ::write(master_fd_, outbox_.data(), budget);
    if (w > 0) {
        outbox_.erase(0, std::size_t(w));
        if (baud_pacing_) {
            credit_bytes_ -= double(w);
        }
    }
    // Personne ne lit et le tampon du pty est plein : on jette, plutôt que de
    // bloquer, et on le comptabilise.
    if (outbox_.size() > 65536) {
        dropped_ += outbox_.size() - 65536;
        outbox_.erase(0, outbox_.size() - 65536);
    }
}

}  // namespace ssemu

#endif  // _WIN32
