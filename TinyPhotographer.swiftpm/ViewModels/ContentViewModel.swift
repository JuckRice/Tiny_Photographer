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
    func didCaptureFrame(image: CIImage, depthMap: CVPixelBuffer?) {
        frameCount += 1
        guard frameCount % processInterval == 0 else { return }
        
        // 我们必须同时拥有深度图才能进行有意义的融合
        guard let depthData = depthMap else { return }
        
        // 1. 让大脑去分析画面，并在闭包中接收分析出的 MLMultiArray 掩码
        mlManager.predict(image: image) { [weak self] segmentationMask in
            guard let self = self, let mask = segmentationMask else { return }
            
            // 2. 将深度图和语义掩码结合起来分析！
            self.fuseDepthAndSemantics(depthMap: depthData, segmentationMask: mask)
        }
    }
    
    // MARK: - 核心融合算法
    private func fuseDepthAndSemantics(depthMap: CVPixelBuffer, segmentationMask: MLMultiArray) {
        // 锁定内存以读取深度数据
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        
        // 假设 DeepLabV3 的输出形状是 [1, 513, 513] 或 [513, 513]
        // 我们取最后一维的尺寸作为宽度和高度
        let shapeCount = segmentationMask.shape.count
        let segWidth = segmentationMask.shape[shapeCount - 1].intValue
        let segHeight = segmentationMask.shape[shapeCount - 2].intValue
        
        // 算法步骤 1：在深度图的中心区域寻找最近的障碍物点
        var minDistance: Float = 999.0 // 初始化为一个很大的距离
        var closestPoint: (x: Int, y: Int) = (depthWidth / 2, depthHeight / 2)
        
        // 我们不遍历整个屏幕，只扫描中间 1/3 的区域，这是盲人行进最关注的区域
        let startY = depthHeight / 3
        let endY = (depthHeight / 3) * 2
        let startX = depthWidth / 3
        let endX = (depthWidth / 3) * 2
        
        for y in startY..<endY {
            for x in startX..<endX {
                let index = y * depthWidth + x
                let distance = floatBuffer[index]
                
                // 忽略无效的深度值 (有些无效点会返回 0 或 NaN)
                if distance > 0.1 && distance < minDistance {
                    minDistance = distance
                    closestPoint = (x, y)
                }
            }
        }
        
        // 如果最近的距离还是大于 2 米，说明前方比较安全，无需报警
        guard minDistance < 2.0 else {
            DispatchQueue.main.async {
                self.warningMessage = "前方路线畅通"
                self.isDangerClose = false
            }
            return
        }
        
        // 算法步骤 2：坐标映射！将深度图上的最近点坐标转换为分割掩码上的坐标
        let mappedX = Int(Float(closestPoint.x) / Float(depthWidth) * Float(segWidth))
        let mappedY = Int(Float(closestPoint.y) / Float(depthHeight) * Float(segHeight))
        
        // 算法步骤 3：读取该像素点的物体类别
        // MLMultiArray 的读取需要将坐标转为 NSNumber 数组
        let maskIndex = [NSNumber(value: mappedY), NSNumber(value: mappedX)]
        let classIdNumber = segmentationMask[maskIndex] // 获取类别 ID (例如 15)
        let classId = classIdNumber.intValue
        
        // 将数字 ID 翻译成人类听得懂的语言
        let objectName = getObjectName(from: classId)
        
        // 算法步骤 4：更新 UI
        DispatchQueue.main.async {
            self.warningMessage = "⚠️ 警告：前方 \(String(format: "%.1f", minDistance)) 米处有【\(objectName)】"
            self.isDangerClose = true
        }
    }
    
    // 辅助方法：将 DeepLabV3 的类别 ID 转换为字符串 (DeepLabV3 默认使用 PASCAL VOC 数据集)
    private func getObjectName(from classId: Int) -> String {
        // PASCAL VOC 共有 21 个类别 (0是背景)
        let classes = [
            0: "空旷区域", 1: "飞机", 2: "自行车", 3: "鸟", 4: "船",
            5: "瓶子", 6: "公交车", 7: "汽车", 8: "猫", 9: "椅子",
            10: "牛", 11: "餐桌", 12: "狗", 13: "马", 14: "摩托车",
            15: "人", 16: "盆栽", 17: "羊", 18: "沙发", 19: "火车", 20: "显示器"
        ]
        
        return classes[classId] ?? "未知障碍物"
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