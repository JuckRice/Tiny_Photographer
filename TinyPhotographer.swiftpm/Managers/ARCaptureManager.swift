import Foundation
import ARKit
import CoreVideo
import CoreImage

/// 定义一个通信协议，用于把 ARKit 抓取到的画面和深度数据源源不断地传出去
protocol ARCaptureDelegate: AnyObject {
    func didCaptureFrame(image: CIImage, depthMap: CVPixelBuffer?)
}

/// 负责管理摄像头和 LiDAR 深度传感器的类
class ARCaptureManager: NSObject, ARSessionDelegate {
    
    // ARKit 的核心：负责管理所有的摄像头追踪和数据流
    private let arSession = ARSession()
    
    // 代理：用于将获取到的数据传送给 ViewModel 处理
    weak var delegate: ARCaptureDelegate?
    
    override init() {
        super.init()
        // 将自己设置为 ARSession 的代理，这样每当有新画面时，系统就会通知我们
        arSession.delegate = self
    }
    
    /// 开启摄像头和 LiDAR
    func startSession() {
        // 1. 安全检查：确认当前设备是否真的支持 LiDAR 深度获取
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("⚠️ 警告：当前设备或配置不支持 LiDAR 深度数据 (SceneDepth)。")
            return
        }
        
        // 2. 创建环境追踪配置
        let configuration = ARWorldTrackingConfiguration()
        
        // 3. 关键步骤：明确告诉 ARKit 我们需要 LiDAR 的深度数据
        configuration.frameSemantics = .sceneDepth
        
        // 4. 启动会话
        arSession.run(configuration)
        print("✅ ARKit 会话已启动，LiDAR 深度追踪已准备就绪！")
    }
    
    /// 停止摄像头 (例如应用进入后台时，节省电量)
    func stopSession() {
        arSession.pause()
        print("⏸️ ARKit 会话已暂停。")
    }
    
    // MARK: - ARSessionDelegate 方法
    
    /// 这个方法极其重要：摄像头每捕获到一帧新画面（通常每秒60次），系统就会调用一次这个方法
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 1. 获取 RGB 彩色图像 (CVPixelBuffer 格式)
        let pixelBuffer = frame.capturedImage
        
        // 将其转换为 CIImage，因为我们之前的 Vision 框架 (DeepLabV3) 需要 CIImage 格式
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // 2. 获取 LiDAR 深度图矩阵
        var depthMapBuffer: CVPixelBuffer? = nil
        if let sceneDepth = frame.sceneDepth {
            // depthMap 是一个包含了每一个像素点距离（单位：米）的矩阵
            depthMapBuffer = sceneDepth.depthMap
        }
        
        // 3. 将准备好的 彩色图像 和 LiDAR深度数据 发送出去
        delegate?.didCaptureFrame(image: ciImage, depthMap: depthMapBuffer)
    }
}