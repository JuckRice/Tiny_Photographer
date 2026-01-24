import SwiftUI
import SpriteKit
import Combine

// MARK: - 1. 数据模型与状态管理 (The Brain)
// 管理任务、相册和游戏状态
class GameContext: ObservableObject {
    @Published var quests: [Quest] = [
        Quest(id: UUID(), title: "寻找一只红色的蝴蝶", targetName: "Butterfly", isCompleted: false),
        Quest(id: UUID(), title: "拍摄森林的入口", targetName: "ForestEntrance", isCompleted: false)
    ]
    
    @Published var photos: [PhotoItem] = []
    @Published var isCameraOpen: Bool = false
    
    // 模拟拍照逻辑
    func capturePhoto(targetInView: String?) {
        let timestamp = Date()
        let color = targetInView != nil ? Color.red : Color.gray
        
        // 如果拍到了目标，尝试完成任务
        if let target = targetInView {
            completeQuest(targetName: target)
        }
        
        // 保存照片（这里暂时用色块代替真实截图）
        let newPhoto = PhotoItem(color: color, timestamp: timestamp, description: targetInView ?? "Nothing")
        photos.insert(newPhoto, at: 0)
    }
    
    private func completeQuest(targetName: String) {
        if let index = quests.firstIndex(where: { $0.targetName == targetName && !$0.isCompleted }) {
            quests[index].isCompleted = true
            print("Quest Completed: \(quests[index].title)")
        }
    }
}

struct Quest: Identifiable {
    let id: UUID
    let title: String
    let targetName: String // 对应 SpriteKit 中的 Node Name
    var isCompleted: Bool
}

struct PhotoItem: Identifiable {
    let id = UUID()
    let color: Color // 暂时用颜色代替 Image
    let timestamp: Date
    let description: String
}

// MARK: - 2. 游戏场景 (The World - SpriteKit)
// 负责渲染 2D 小人、蝴蝶和移动逻辑
class WorldScene: SKScene {
    // 这是一个钩子，用来告诉 SwiftUI 现在的相机看到了什么
    var onSubjectInFocus: ((String?) -> Void)?
    
    let player = SKShapeNode(circleOfRadius: 15)
    let butterfly = SKShapeNode(rectOf: CGSize(width: 20, height: 20))
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.95, green: 0.98, blue: 0.90, alpha: 1.0) // 米白色背景
        
        // 设置玩家
        player.fillColor = .systemBlue
        player.position = CGPoint(x: frame.midX, y: frame.midY)
        addChild(player)
        
        // 设置目标（蝴蝶）
        butterfly.name = "Butterfly"
        butterfly.fillColor = .systemRed
        butterfly.position = CGPoint(x: frame.midX + 100, y: frame.midY + 100)
        // 给蝴蝶加个简单的飞舞动画
        let moveAction = SKAction.moveBy(x: 20, y: 20, duration: 1.0)
        butterfly.run(SKAction.repeatForever(SKAction.sequence([moveAction, moveAction.reversed()])))
        addChild(butterfly)
    }
    
    // 简单的点击移动逻辑
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        
        let moveAction = SKAction.move(to: location, duration: 0.5)
        player.run(moveAction)
    }
    
    // 每一帧检测：玩家是否靠近了蝴蝶？(模拟相机对焦)
    override func update(_ currentTime: TimeInterval) {
        // 计算玩家和蝴蝶的距离
        let distance = hypot(player.position.x - butterfly.position.x, player.position.y - butterfly.position.y)
        
        // 假设相机射程是 150 像素
        if distance < 150 {
            onSubjectInFocus?("Butterfly")
        } else {
            onSubjectInFocus?(nil)
        }
    }
}

// MARK: - 3. UI 界面 (The Lens - SwiftUI)
struct ContentView: View {
    @StateObject var context = GameContext()
    @State private var flashOpacity: Double = 0.0
    
    // 创建场景
    var scene: SKScene {
        let scene = WorldScene()
        scene.size = CGSize(width: 400, height: 600)
        scene.scaleMode = .aspectFill
        // 绑定回调：当 SpriteKit 里的物体进入范围，更新 SwiftUI
        scene.onSubjectInFocus = { subject in
            self.currentFocus = subject
        }
        return scene
    }
    
    @State private var currentFocus: String? = nil
    
    var body: some View {
        ZStack {
            //Layer 1: 游戏世界
            SpriteView(scene: scene)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // 拦截点击，或者在这里处理
                }
            
            // Layer 2: HUD (非相机模式)
            if !context.isCameraOpen {
                VStack {
                    HStack {
                        QuestListView(quests: context.quests)
                        Spacer()
                    }
                    .padding()
                    Spacer()
                    
                    // 打开相机按钮
                    Button(action: {
                        withAnimation { context.isCameraOpen = true }
                    }) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                            .padding()
                            .background(Circle().fill(Color.white).shadow(radius: 5))
                    }
                    .padding(.bottom, 30)
                }
            }
            
            // Layer 3: 相机取景器模式
            if context.isCameraOpen {
                CameraOverlayView(
                    isPresented: $context.isCameraOpen,
                    focusSubject: currentFocus,
                    onShutter: {
                        triggerShutter()
                    }
                )
            }
            
            // Layer 4: 闪光灯特效
            Color.white
                .ignoresSafeArea()
                .opacity(flashOpacity)
        }
    }
    
    // 快门逻辑
    func triggerShutter() {
        // 1. 播放闪光动画
        withAnimation(.easeIn(duration: 0.1)) { flashOpacity = 1.0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.3)) { flashOpacity = 0.0 }
        }
        
        // 2. 数据层捕捉
        context.capturePhoto(targetInView: currentFocus)
    }
}

// 子视图：任务列表
struct QuestListView: View {
    var quests: [Quest]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今日委托").font(.headline).foregroundColor(.black)
            ForEach(quests) { quest in
                HStack {
                    Image(systemName: quest.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(quest.isCompleted ? .green : .gray)
                    Text(quest.title)
                        .strikethrough(quest.isCompleted)
                        .font(.caption)
                        .foregroundColor(.black)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.8))
        .cornerRadius(12)
    }
}

// 子视图：相机遮罩层
struct CameraOverlayView: View {
    @Binding var isPresented: Bool
    var focusSubject: String?
    var onShutter: () -> Void
    
    var body: some View {
        ZStack {
            // 半透明遮罩
            Color.black.opacity(0.3).edgesIgnoringSafeArea(.all)
            
            VStack {
                // 顶部退出按钮
                HStack {
                    Button("关闭") {
                        withAnimation { isPresented = false }
                    }
                    .foregroundColor(.white)
                    .padding()
                    Spacer()
                }
                
                Spacer()
                
                // 取景框中心
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 300, height: 300)
                    
                    // 对焦提示
                    if let subject = focusSubject {
                        Text("检测到: \(subject)")
                            .padding(5)
                            .background(Color.black.opacity(0.5))
                            .foregroundColor(.yellow)
                            .offset(y: -130)
                    }
                    
                    // 准星
                    Image(systemName: "plus")
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Spacer()
                
                // 快门按钮
                Button(action: onShutter) {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 4)
                        .background(Circle().fill(Color.red))
                        .frame(width: 70, height: 70)
                }
                .padding(.bottom, 30)
            }
        }
    }
}
