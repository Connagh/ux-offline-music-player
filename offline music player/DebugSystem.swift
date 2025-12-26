import SwiftUI
import Combine

// MARK: - Logger

class Logger: ObservableObject {
    static let shared = Logger()
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: LogLevel
        let message: String
        
        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }
    
    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .info: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
    
    @Published var logs: [LogEntry] = []
    
    private init() {}
    
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        DispatchQueue.main.async {
            self.logs.append(entry)
            // Keep log size manageable
            if self.logs.count > 1000 {
                self.logs.removeFirst()
            }
        }
        print("[\(level.rawValue)] \(message)")
    }
    
    func clear() {
        logs.removeAll()
    }
}

// MARK: - Debug View

struct DebugView: View {
    @ObservedObject var logger = Logger.shared
    @State private var memoryUsage: String = "Calculating..."
    @State private var timer: Timer?
    @ObservedObject var bookmarkManager: BookmarkManager // To show object stats
    
    var body: some View {
        VStack(spacing: 0) {
            // Stats Header
            VStack(alignment: .leading, spacing: 8) {
                Text("System Diagnostics")
                    .font(.headline)
                    .foregroundColor(.white)
                
                HStack {
                    VStack(alignment: .leading) {
                        Text("Memory Usage")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(memoryUsage)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.offlineOrange)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Songs Loaded")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(bookmarkManager.songs.count)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                     
                    VStack(alignment: .trailing) {
                        Text("Folders")
                            .font(.caption)
                            .foregroundColor(.gray)
                         Text("\(bookmarkManager.folders.count)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding()
            .background(Color.offlineDarkGray)
            
            // Counsel Output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logger.logs) { log in
                            HStack(alignment: .top, spacing: 8) {
                                Text(log.formattedTime)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .frame(width: 70, alignment: .leading)
                                
                                Text("[\(log.level.rawValue)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(log.level.color)
                                    .frame(width: 40, alignment: .leading)
                                
                                Text(log.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .id(log.id)
                        }
                    }
                }
                .onChange(of: logger.logs.count) {
                    if let last = logger.logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .background(Color.black)
            
            // Toolbar
            HStack {
                Button("Clear Logs") {
                    logger.clear()
                }
                .padding()
                .foregroundColor(.red)
                
                Spacer()
            }
            .background(Color.offlineDarkGray)
        }
        .navigationTitle("Debug Console")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateMemoryUsage()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let usedMB = Double(info.resident_size) / 1024.0 / 1024.0
            memoryUsage = String(format: "%.1f MB", usedMB)
        } else {
            memoryUsage = "Error"
        }
    }
}
