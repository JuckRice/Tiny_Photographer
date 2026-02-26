import Foundation
import CoreML
import Vision
import CoreImage

/// 🧠 大脑模块：负责管理 DeepLabV3 模型，将图像转换为语义分割掩码矩阵
class SemanticSegmentationManager: ObservableObject {
    
    // 用于通知外部 (比如 UI) 模型是否已经准备就绪
    @Published var isModelLoaded: Bool = false
    
    // Vision 框架的核心对象
    private var visionModel: VNCoreMLModel?
    private var segmentationRequest: VNCoreMLRequest?
    
    init() {
        // 在类初始化时，立刻在后台加载模型
        setupModel()
    }
    
    /// 步骤 1：加载 Core ML 模型并配置 Vision 请求
    private func setupModel() {
        // 在后台线程加载模型，防止阻塞主线程导致 App 启动卡顿
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 1a. 配置模型参数 (使用默认配置)
                let configuration = MLModelConfiguration()
                
                // 1b. 实例化 Xcode 自动生成的 DeepLabV3 类
                // ⚠️ 注意：如果你下载的模型文件名叫 "DeepLabV3FP16.mlmodel"，这里的类名就是 DeepLabV3FP16
                let coreMLModel = try DeepLabV3(configuration: configuration)
                
                // 1c. 将 Core ML 模型包装为 Vision 框架可以识别的格式
                let vModel = try VNCoreMLModel(for: coreMLModel.model)
                
                // 1d. 创建 Vision 图像处理请求
                let request = VNCoreMLRequest(model: vModel)
                
                // 1e. 配置图像缩放选项
                // .scaleFill 会自动把摄像头画面拉伸成模型需要的正方形 (如 513x513)
                request.imageCropAndScaleOption = .scaleFill
                
                // 将局部变量赋值给类的属性
                self.visionModel = vModel
                self.segmentationRequest = request
                
                // 回到主线程更新状态
                DispatchQueue.main.async {
                    self.isModelLoaded = true
                    print("✅ DeepLabV3 模型与 Vision 请求初始化成功！")
                }
                
            } catch {
                print("❌ 初始化模型失败: \(error.localizedDescription)")
            }
        }
    }
    
    /// 步骤 2：接收外部传入的图像，执行预测，并将结果矩阵通过闭包返回
    /// - Parameters:
    ///   - image: 需要分析的图像 (来自 ARCaptureManager)
    ///   - completion: 预测完成后的回调闭包，回传包含类别标签的多维数组
    func predict(image: CIImage, completion: @escaping (MLMultiArray?) -> Void) {
        // 确保模型和请求已经加载完毕
        guard let request = segmentationRequest else {
            print("⚠️ 警告：分割请求尚未初始化。")
            completion(nil)
            return
        }
        
        // 创建图像处理的执行者
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        
        // 在后台线程执行这件极其消耗算力的预测任务
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // 命令 Vision 框架开始分析图像
                try handler.perform([request])
                
                // 分析完成后，提取结果
                // DeepLabV3 的结果是 VNCoreMLFeatureValueObservation 类型
                if let observations = request.results as? [VNCoreMLFeatureValueObservation],
                   let featureValue = observations.first?.featureValue,
                   let multiArray = featureValue.multiArrayValue {
                    
                    // 成功获取矩阵！通过闭包将数据传回给 ContentViewModel
                    completion(multiArray)
                    
                } else {
                    print("⚠️ 无法从模型结果中提取 MLMultiArray。")
                    completion(nil)
                }
                
            } catch {
                print("❌ 执行图像分割预测失败: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}