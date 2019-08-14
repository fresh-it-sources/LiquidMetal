//
//  ViewController.swift
//  LiquidMetal
//
//  Created by majess on 14/08/2019.
//  Copyright © 2019 Fresh IT. All rights reserved.
//

import UIKit
import MetalKit
import CoreMotion

class ViewController: UIViewController {

    //MARK: - Box2D variables
    let gravity: Float = 9.80665
    let ptmRatio: Float = 32.0
    let particleRadius: Float = 9
    var particleSystem: UnsafeMutableRawPointer?
    
    let screenSize: CGSize = UIScreen.main.bounds.size
    var screenWidth: Float {
        get {
            return Float(screenSize.width)
        }
    }
    var screenHeight: Float {
        get {
            return Float(screenSize.height)
        }
    }
    
    // MARK: - Metal variables
    var device: MTLDevice! = nil
    var metalLayer: CAMetalLayer! = nil
    
    var particleCount: Int = 0
    var vertexBuffer: MTLBuffer! = nil
    var uniformBuffer: MTLBuffer! = nil
    
    var pipelineState: MTLRenderPipelineState! = nil
    var commandQueue: MTLCommandQueue! = nil
    
    // MARK: - Core motion
    let motionManager: CMMotionManager = CMMotionManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        LiquidFun.createWorld(withGravity: Vector2D(x: 0, y: -gravity))
        
        particleSystem = LiquidFun.createParticleSystem(withRadius: particleRadius/ptmRatio,
                                                        dampingStrength: 0.2,
                                                        gravityScale: 1,
                                                        density: 1.2)

        if let particles = particleSystem {
            LiquidFun.createParticleBox(forSystem: particles,
                                        position: Vector2D(x: screenWidth * 0.5 / ptmRatio,
                                                           y: screenHeight * 0.5 / ptmRatio),
                                        size: Size2D(width: 50 / ptmRatio, height: 50 / ptmRatio))
            LiquidFun.setParticleLimitForSystem(particles, maxParticles: 1500)
        }
        
        LiquidFun.createEdgeBox(withOrigin: Vector2D(x: 0, y: 0), size: Size2D(width: screenWidth / ptmRatio, height: screenHeight / ptmRatio))
        
        //self.printParticleInfo()
        createMetalLayer()
        refreshVertexBuffer()
        refreshUniformBuffer()
        buildRenderPipeline()
        
        render()
        
        let displaylink = CADisplayLink(target: self, selector: #selector(update))
        displaylink.preferredFramesPerSecond = 30
        displaylink.add(to: RunLoop.current, forMode: RunLoop.Mode.default)
        
        motionManager.startAccelerometerUpdates(to: OperationQueue()) { (accelerometerData, error) in
            let acceleration = accelerometerData?.acceleration
            let gravityX = self.gravity * Float(acceleration?.x ?? 0.0)
            let gravityY = self.gravity * Float(acceleration?.y ?? 0.0)
            LiquidFun.setGravity(Vector2D(x: gravityX, y: gravityY))
        }
    }
    
    deinit {
        LiquidFun.destroyWorld()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touchObject in touches {
            let touchLocation = touchObject.location(in: view)
            let position = Vector2D(x: Float(touchLocation.x) / ptmRatio,
                                    y: Float(view.bounds.height - touchLocation.y) / ptmRatio)
            let size = Size2D(width: 100 / ptmRatio, height: 100 / ptmRatio)

            LiquidFun.createParticleBox(forSystem: particleSystem!, position: position, size: size)
        }
    }

    func printParticleInfo() {
        if let particlesSystem = particleSystem {
            let count = Int(LiquidFun.particleCount(forSystem: particlesSystem))
            print("There are \(count) particles present")
            
            let unsafeMutableRawPointer: UnsafeMutableRawPointer = LiquidFun.particlePositions(forSystem: particlesSystem)
            let positions: UnsafeMutablePointer<Vector2D> = unsafeMutableRawPointer.bindMemory(to: Vector2D.self, capacity: count)
            
            for i in 0..<count {
                let position = positions[i]
                print("particle: \(i) position: (\(position.x), \(position.y))")
            }
        }
    }
    
    func createMetalLayer() {
        device = MTLCreateSystemDefaultDevice()
        
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.frame = view.layer.frame
        view.layer.addSublayer(metalLayer)
    }
    
    func refreshVertexBuffer() {
        if let particlesSystem = particleSystem {
            particleCount = Int(LiquidFun.particleCount(forSystem: particlesSystem))
            let positions = LiquidFun.particlePositions(forSystem: particlesSystem)
            let floatSize = MemoryLayout<Float>.size
            let bufferSize = floatSize * particleCount * 2
            
            vertexBuffer = device.makeBuffer(bytes: positions, length: bufferSize, options: [])
        }
    }
    
    func makeOrthographicMatrix(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> [Float] {
        let ral = right + left
        let rsl = right - left
        let tab = top + bottom
        let tsb = top - bottom
        let fan = far + near
        let fsn = far - near
        
        return [2.0 / rsl, 0.0, 0.0, 0.0,
                0.0, 2.0 / tsb, 0.0, 0.0,
                0.0, 0.0, -2.0 / fsn, 0.0,
                -ral / rsl, -tab / tsb, -fan / fsn, 1.0]
    }
    
    func refreshUniformBuffer () {
        let ndcMatrix = makeOrthographicMatrix(left: 0, right: screenWidth, bottom: 0, top: screenHeight, near: -1, far: 1)
        var radius = particleRadius
        var ratio = ptmRatio
        
        let floatSize = MemoryLayout<Float>.size
        let float4x4ByteAlignment = floatSize * 4
        let float4x4Size = floatSize * 16
        let paddingBytesSize = float4x4ByteAlignment - floatSize * 2
        let uniformStructSize = float4x4Size + floatSize * 2 + paddingBytesSize
        
        uniformBuffer = device.makeBuffer(length: uniformStructSize, options: [])
        let bufferPointer = uniformBuffer.contents()
        memcpy(bufferPointer, ndcMatrix, float4x4Size)
        memcpy(bufferPointer + float4x4Size, &ratio, floatSize)
        memcpy(bufferPointer + float4x4Size + floatSize, &radius, floatSize)
    }
    
    func buildRenderPipeline() {
        let defaultLibrary = device.makeDefaultLibrary()
        let fragmentProgram = defaultLibrary?.makeFunction(name: "basic_fragment")
        let vertexProgram = defaultLibrary?.makeFunction(name: "particle_vertex")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexProgram
        pipelineDescriptor.fragmentFunction = fragmentProgram
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }catch{
            print("\(error)")
        }
        
        commandQueue = device.makeCommandQueue()
    }
    
    func render() {
        let drawable = metalLayer.nextDrawable()
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable?.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 104.0/255.0, blue: 5.0/255.0, alpha: 1.0)
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        
        if let renderEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
            renderEncoder.setRenderPipelineState(pipelineState)
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            
            renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount, instanceCount: 1)
            renderEncoder.endEncoding()
        }
        
        guard let draw = drawable else { fatalError() }
        commandBuffer?.present(draw)
        
        commandBuffer?.commit()
    }
    
    
    @objc func update(displaylink: CADisplayLink) {
        autoreleasepool {
            LiquidFun.worldStep(displaylink.duration, velocityIterations: 8, positionIterations: 3)
            self.refreshVertexBuffer()
            self.render()
        }
    }
}

