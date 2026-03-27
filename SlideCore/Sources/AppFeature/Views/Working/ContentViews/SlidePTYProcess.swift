import Dispatch
import Foundation
import Darwin

// Portions of the PTY launch helpers are adapted from SwiftTerm's Pty.swift
// and LocalProcess.swift, which are distributed under the MIT License.

protocol SlidePTYProcessDelegate: AnyObject {
    func initialWindowSize(for process: SlidePTYProcess) -> winsize
    func ptyProcess(_ process: SlidePTYProcess, didReceive data: Data)
    func ptyProcess(_ process: SlidePTYProcess, didTerminateWith exitCode: Int32?)
}

final class SlidePTYProcess: @unchecked Sendable {
    private let lock = NSLock()
    private weak var delegate: SlidePTYProcessDelegate?
    private let readQueue = DispatchQueue(label: "com.longtaillabs.slide.terminal.pty.read")
    private let writeQueue = DispatchQueue(label: "com.longtaillabs.slide.terminal.pty.write")
    private let processQueue = DispatchQueue(label: "com.longtaillabs.slide.terminal.pty.process")

    private var childPid: pid_t = 0
    private var masterFileDescriptor: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?
    private var running = false
    private var didNotifyTermination = false

    init(delegate: SlidePTYProcessDelegate) {
        self.delegate = delegate
    }

    deinit {
        terminate()
        cleanup(closeFileDescriptor: true)
    }

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    func start(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String?
    ) {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        lock.unlock()

        var windowSize = delegate?.initialWindowSize(for: self)
            ?? winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let argv = [executable] + args

        guard let launchResult = Self.fork(
            executable: executable,
            args: argv,
            environment: environment,
            currentDirectory: currentDirectory,
            desiredWindowSize: &windowSize
        ) else {
            notifyTermination(exitCode: nil)
            return
        }

        configureMasterFileDescriptor(launchResult.masterFd)

        lock.lock()
        childPid = launchResult.pid
        masterFileDescriptor = launchResult.masterFd
        running = true
        didNotifyTermination = false
        lock.unlock()

        installReadSource(fileDescriptor: launchResult.masterFd)
        installProcessSource(pid: launchResult.pid)
    }

    func send(_ data: Data) {
        guard !data.isEmpty else { return }
        let fileDescriptor = currentMasterFileDescriptor()
        guard fileDescriptor >= 0 else { return }

        writeQueue.async {
            data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                var written = 0

                while written < data.count {
                    let result = Darwin.write(
                        fileDescriptor,
                        baseAddress.advanced(by: written),
                        data.count - written
                    )

                    if result > 0 {
                        written += result
                        continue
                    }

                    if result == -1, errno == EINTR {
                        continue
                    }

                    if result == -1, errno == EAGAIN || errno == EWOULDBLOCK {
                        usleep(1_000)
                        continue
                    }

                    return
                }
            }
        }
    }

    func resize(windowSize: winsize) {
        let fileDescriptor = currentMasterFileDescriptor()
        guard fileDescriptor >= 0 else { return }

        var windowSize = windowSize
        _ = ioctl(fileDescriptor, TIOCSWINSZ, &windowSize)
    }

    func terminate() {
        let pid = currentChildPid()
        guard pid > 0 else { return }
        _ = Darwin.kill(pid, SIGTERM)
    }

    private func installReadSource(fileDescriptor: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: readQueue)
        source.setEventHandler { [weak self] in
            self?.handleReadableData()
        }
        source.resume()

        lock.lock()
        readSource = source
        lock.unlock()
    }

    private func installProcessSource(pid: pid_t) {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: processQueue)
        source.setEventHandler { [weak self] in
            self?.handleProcessExit(for: pid)
        }
        source.resume()

        lock.lock()
        processSource = source
        lock.unlock()
    }

    private func handleReadableData() {
        let fileDescriptor = currentMasterFileDescriptor()
        guard fileDescriptor >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)

            if bytesRead > 0 {
                delegate?.ptyProcess(self, didReceive: Data(buffer.prefix(Int(bytesRead))))
                continue
            }

            if bytesRead == 0 {
                return
            }

            if errno == EINTR {
                continue
            }

            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EIO {
                return
            }

            return
        }
    }

    private func handleProcessExit(for pid: pid_t) {
        var status: Int32 = 0
        var waitResult: pid_t = 0

        repeat {
            waitResult = waitpid(pid, &status, 0)
        } while waitResult == -1 && errno == EINTR

        cleanup(closeFileDescriptor: true)

        guard waitResult == pid else {
            notifyTermination(exitCode: nil)
            return
        }

        notifyTermination(exitCode: Self.decodeExitCode(from: status))
    }

    private func currentMasterFileDescriptor() -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return running ? masterFileDescriptor : -1
    }

    private func currentChildPid() -> pid_t {
        lock.lock()
        defer { lock.unlock() }
        return running ? childPid : 0
    }

    private func cleanup(closeFileDescriptor: Bool) {
        let fileDescriptor: Int32
        let readSource: DispatchSourceRead?
        let processSource: DispatchSourceProcess?

        lock.lock()
        running = false
        fileDescriptor = masterFileDescriptor
        readSource = self.readSource
        processSource = self.processSource
        masterFileDescriptor = -1
        childPid = 0
        self.readSource = nil
        self.processSource = nil
        lock.unlock()

        readSource?.cancel()
        processSource?.cancel()

        if closeFileDescriptor, fileDescriptor >= 0 {
            _ = Darwin.close(fileDescriptor)
        }
    }

    private func notifyTermination(exitCode: Int32?) {
        lock.lock()
        guard !didNotifyTermination else {
            lock.unlock()
            return
        }
        didNotifyTermination = true
        lock.unlock()

        delegate?.ptyProcess(self, didTerminateWith: exitCode)
    }

    private func configureMasterFileDescriptor(_ fileDescriptor: Int32) {
        let fileStatusFlags = fcntl(fileDescriptor, F_GETFL)
        if fileStatusFlags >= 0 {
            _ = fcntl(fileDescriptor, F_SETFL, fileStatusFlags | O_NONBLOCK)
        }

        let fileDescriptorFlags = fcntl(fileDescriptor, F_GETFD)
        if fileDescriptorFlags >= 0 {
            _ = fcntl(fileDescriptor, F_SETFD, fileDescriptorFlags | FD_CLOEXEC)
        }
    }

    private static func decodeExitCode(from status: Int32) -> Int32? {
        let signal = status & 0x7F

        if signal == 0 {
            return (status >> 8) & 0xFF
        }

        if signal != 0x7F {
            return 128 + signal
        }

        return nil
    }
}

private extension SlidePTYProcess {
    struct LaunchResult {
        let pid: pid_t
        let masterFd: Int32
    }

    struct CStringArray {
        let base: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
        let count: Int
    }

    static func allocateCStringArray(_ strings: [String]) -> CStringArray? {
        let base = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        var initializedCount = 0

        for (index, string) in strings.enumerated() {
            guard let duplicated = strdup(string) else {
                for cleanupIndex in 0..<initializedCount {
                    free(base[cleanupIndex])
                }
                base.deallocate()
                return nil
            }
            base[index] = duplicated
            initializedCount += 1
        }

        base[strings.count] = nil
        return CStringArray(base: base, count: strings.count)
    }

    static func freeCStringArray(_ array: CStringArray) {
        for index in 0..<array.count {
            free(array.base[index])
        }
        array.base.deallocate()
    }

    static func fork(
        executable: String,
        args: [String],
        environment: [String],
        currentDirectory: String?,
        desiredWindowSize: inout winsize
    ) -> LaunchResult? {
        guard let cArgs = allocateCStringArray(args) else {
            return nil
        }
        guard let cEnv = allocateCStringArray(environment) else {
            freeCStringArray(cArgs)
            return nil
        }
        guard let cExecutable = strdup(executable) else {
            freeCStringArray(cEnv)
            freeCStringArray(cArgs)
            return nil
        }

        var cCurrentDirectory: UnsafeMutablePointer<CChar>?
        if let currentDirectory {
            guard let duplicatedCurrentDirectory = strdup(currentDirectory) else {
                free(cExecutable)
                freeCStringArray(cEnv)
                freeCStringArray(cArgs)
                return nil
            }
            cCurrentDirectory = duplicatedCurrentDirectory
        }

        defer {
            freeCStringArray(cArgs)
            freeCStringArray(cEnv)
            free(cExecutable)
            if let cCurrentDirectory {
                free(cCurrentDirectory)
            }
        }

        var masterFileDescriptor: Int32 = 0
        let pid = forkpty(&masterFileDescriptor, nil, nil, &desiredWindowSize)

        guard pid >= 0 else {
            return nil
        }

        if pid == 0 {
            if let cCurrentDirectory {
                _ = chdir(cCurrentDirectory)
            }

            _ = execve(cExecutable, cArgs.base, cEnv.base)
            _exit(127)
        }

        return LaunchResult(pid: pid, masterFd: masterFileDescriptor)
    }
}
