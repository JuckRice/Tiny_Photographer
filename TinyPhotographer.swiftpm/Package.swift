// swift-tools-version: 5.8

// 警告：这段代码是用于 Mac/iPad 解析的包描述文件
import PackageDescription
import AppleProductTypes

let package = Package(
    name: "VisionAssist",
    platforms: [
        .iOS("16.0") // 设置最低支持系统版本
    ],
    products: [
        .iOSApplication(
            name: "VisionAssist",
            targets: ["AppModule"],
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .camera),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            // 声明我们需要使用相机，这是必须的权限！
            capabilities: [
                .camera(purposeString: "我们需要使用摄像头和 LiDAR 来分析您前方的环境。")
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)