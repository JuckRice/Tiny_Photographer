import Foundation
import CoreImage
import CoreVideo
import Combine

/// 它是前端 UI (View) 和后端逻辑 (Managers) 之间的桥梁
class ContentViewModel: ObservableObject, ARCaptureDelegate {
    
    // MARK: - 给 UI 订阅的公开状态 (@Published)
    // 当这些值改变时，SwiftUI 界面会自动刷新
    @Published var warningMessage: String = "正在扫描环境..."
    @Published var isDangerClose: Bool = false
    
    // MARK: - 核心管理器实例
    private let arManager = ARCaptureManager()
    private let mlManager = SemanticSegmentationManager()
    
    // 用于控制处理频率（不要每秒处理 60 帧，设备会吃不消）
    private var frameCount = 0
    private let processInterval = 10 // 每 10 帧处理一次 (大约一秒处理 6 次)
    
    init() {
        // 1. 设置代理：告诉 ARManager "如果有新画面，请交给我处理"
        arManager.delegate = self
    }
    
    // MARK: - 流程控制
    
    /// 供外部 UI 调用的启动方法
    func startScanning() {
        arManager.startSession()
        self.warningMessage = "系统已启动，正在分析前方道路"
    }
    
    /// 供外部 UI 调用的停止方法
    func stopScanning() {
        arManager.stopSession()
        self.warningMessage = "系统已暂停"
        self.isDangerClose = false
    }
    
    // MARK: - ARCaptureDelegate 代理方法实现
    
    /// 当 ARManager 获取到新的一帧图像和深度数据时，会自动触发这个方法
    func didCaptureFrame(image: CIImage, depthMap: CVPixelBuffer?) {
        frameCount += 1
        
        // 性能优化：我们不需要处理摄像头的每一帧。跳帧处理可以极大节省电池和算力
        guard frameCount % processInterval == 0 else { return }
        
        // 1. 让大脑 (CoreML) 去分析画面里有什么
        mlManager.predict(image: image)
        
        // 2. 分析 LiDAR 传来的深度数据 (距离)
        if let depthData = depthMap {
            analyzeDepthAndObstacles(depthMap: depthData)
        }
    }
    
    // MARK: - 核心业务逻辑
    
    /// 分析深度图，判断是否有障碍物太近
    private func analyzeDepthAndObstacles(depthMap: CVPixelBuffer) {
        // 
        // 这里的 depthMap 是一个矩阵，包含了画面中每个点的距离（单位：米）
        
        // TODO: 下一步的难点在这里！
        // 理想的逻辑是：
        // 1. 从 mlManager 获取当前画面的“语义分割掩码”(知道哪里是路，哪里是墙/人)
        // 2. 结合 depthMap (知道墙/人离我们有多远)
        // 3. 如果发现“人”或“墙”的距离小于 1.5 米，触发警报
        
        // 这里我们先写一个简化的逻辑占位：假设我们只检测画面正中心的距离
        let centerDistance = getCenterDistance(from: depthMap)
        
        // 切换到主线程更新 UI 状态 (UI 更新必须在主线程)
        DispatchQueue.main.async {
            if let distance = centerDistance {
                if distance < 1.0 { // 如果中心点物体距离小于 1 米
                    self.warningMessage = "⚠️ 警告：前方 \(String(format: "%.1f", distance)) 米处有障碍物！"
                    self.isDangerClose = true
                } else {
                    self.warningMessage = "前方安全 (\(String(format: "%.1f", distance)) 米)"
                    self.isDangerClose = false
                }
            } else {
                self.warningMessage = "无法获取深度数据"
            }
        }
    }
    
    /// 辅助方法：从深度图中提取中心点的距离 (单位：米)
    private func getCenterDistance(from depthMap: CVPixelBuffer) -> Float? {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        // 找到中心点坐标
        let centerX = width / 2
        let centerY = height / 2
        
        // 深度图通常是 Float32 格式
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        
        // 计算中心点在内存中的偏移量并读取数值
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let index = centerY * width + centerX
        let distanceInMeters = floatBuffer[index]
        
        return distanceInMeters
    }
}