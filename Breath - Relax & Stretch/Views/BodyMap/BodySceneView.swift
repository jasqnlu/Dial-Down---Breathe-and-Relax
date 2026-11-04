import SwiftUI
import SceneKit

// MARK: - Body Rig
//
// Owns the SceneKit scene graph for the rotatable skin-covered body model:
//   sceneRoot
//     ├─ cameraNode        (static — never rotates)
//     ├─ keyLight / fillLight / ambientLight  (static, world-fixed)
//     └─ rigNode           (rotates around Y for the turntable effect)
//          ├─ skinNode     (the skin shell, visible + opaque at rest)
//          ├─ muscleNode   (grayscale muscle pieces, hidden at rest — revealed on tap)
//          └─ marksNode    (marker-dot spheres, normalized-space coords)
//
// At rest, `skinNode` is the only visible surface (taps hit it) and
// `muscleNode.isHidden == true` (hidden geometry is excluded from hit-testing).
// A tap reveals the muscle layer: `muscleNode` unhides and fades in while
// `skinNode` fades to a translucent scrim, then candidate muscles colorize.
//
// `BodySkinMuscle.obj` is PRE-NORMALIZED at export (Y-up, +Z-forward, height 2,
// whole-body recentred), so pieces load at IDENTITY — never recentre/scale
// them here or they'd drift from the hitboxes. Each muscle piece wears a
// neutral grayscale PBR material at rest; candidate highlights tint it on
// reveal. The skin piece wears a soft neutral skin-tone material.
//
// Y is up, the figure's face points toward +Z. Rotation 0 == front, π == back.
// Anatomical left = world +X (the marking system's L/R convention).

nonisolated enum BodyModelStyle {
    case anatomy
    var resourceName: String { "BodySkinMuscle" }
}

/// Colour + blend constants for the muscle-reveal highlight, shared by the base
/// material and the candidate tint so focused / unfocused / neutral states read
/// as one system. Tints lerp the anatomical `baseTone` toward the candidate's
/// `CandidatePalette` accent — keeping base shading visible so neighbouring
/// heads never dissolve into one flat colour block (mirrors the HTML mockup).
nonisolated enum MuscleHighlight {
    /// Neutral grayscale the muscle layer wears at rest — colour is reserved for highlight.
    static let baseTone = UIColor(white: 0.62, alpha: 1)
    /// Soft neutral skin tone the skin shell wears at rest (a reasonable design
    /// default — not spec'd exactly by the brief, easy to retune later).
    static let skinTone = UIColor(red: 0.87, green: 0.74, blue: 0.64, alpha: 1)
    static let unfocusedTint: CGFloat = 0.5
    static let focusedTint: CGFloat = 0.8
    static let unfocusedGlow: CGFloat = 0.12
    static let focusedGlow: CGFloat = 0.42
    /// Skin opacity while a reveal is active (fades to expose the muscle layer).
    static let skinRevealedOpacity: CGFloat = 0.12
    static let revealDuration: TimeInterval = 0.5

    /// Linear blend of two colours in RGB (t = 0 → a, t = 1 → b).
    static func lerp(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let r: CGFloat = ar + (br - ar) * t
        let g: CGFloat = ag + (bg - ag) * t
        let bl: CGFloat = ab + (bb - ab) * t
        return UIColor(red: r, green: g, blue: bl, alpha: 1)
    }
}

/// Parses and caches the (multi-MB) `BodySkinMuscle.obj` into per-object pieces
/// off the main thread. An actor so concurrent loads — e.g. two `BodySceneView`s
/// mounting at once, or a facing flip re-creating the rig mid-load — serialize
/// on the shared `partsCache` instead of racing.
actor BodyMeshLoader {
    static let shared = BodyMeshLoader()
    private var partsCache: [AnatomyPiece]?

    struct AnatomyPiece {
        let name: String
        let layer: String            // "muscle" | "skin"
        let group: String?
        let head: String?
        let faceZone: String?
        let joint: String?
        let sources: [SCNGeometrySource]
        let element: SCNGeometryElement
    }

    func anatomyParts() -> [AnatomyPiece]? {
        if let partsCache { return partsCache }
        guard let url = Bundle.main.url(forResource: BodyModelStyle.anatomy.resourceName, withExtension: "obj"),
              let parts = Self.parseAnatomyOBJ(url: url) else { return nil }
        partsCache = parts
        return parts
    }

    /// Same contiguous-OBJ parser as before, but keeps EVERY mapped node (muscle,
    /// skin) and tags it from the node map. Objects absent from the map or with
    /// no faces are skipped.
    private static func parseAnatomyOBJ(url: URL) -> [AnatomyPiece]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var parts: [AnatomyPiece] = []
        var name: String?
        var vertBase = 0, globalV = 0
        var positions: [SCNVector3] = [], normals: [SCNVector3] = []
        var indices: [Int32] = []
        func flush() {
            guard let name, !indices.isEmpty, let layer = MuscleNodeNames.layerByNode[name] else { return }
            let sources = [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)]
            let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
            parts.append(AnatomyPiece(name: name, layer: layer,
                                      group: MuscleNodeNames.groupByNode[name],
                                      head: MuscleNodeNames.headByNode[name],
                                      faceZone: MuscleNodeNames.faceZoneByNode[name],
                                      joint: MuscleNodeNames.jointByNode[name],
                                      sources: sources, element: element))
        }
        text.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let c = line.dropFirst(2).split(separator: " ")
                if c.count == 3, let x = Float(c[0]), let y = Float(c[1]), let z = Float(c[2]) { positions.append(SCNVector3(x, y, z)) }
                globalV += 1
            } else if line.hasPrefix("vn ") {
                let c = line.dropFirst(3).split(separator: " ")
                if c.count == 3, let x = Float(c[0]), let y = Float(c[1]), let z = Float(c[2]) { normals.append(SCNVector3(x, y, z)) }
            } else if line.hasPrefix("f ") {
                for tok in line.dropFirst(2).split(separator: " ") {
                    let vStr = tok.prefix { $0 != "/" }
                    if let g = Int(vStr) { indices.append(Int32(g - vertBase - 1)) }
                }
            } else if line.hasPrefix("o ") {
                flush(); name = String(line.dropFirst(2)); vertBase = globalV
                positions.removeAll(keepingCapacity: true); normals.removeAll(keepingCapacity: true); indices.removeAll(keepingCapacity: true)
            }
        }
        flush()
        return parts.isEmpty ? nil : parts
    }
}

final class BodyRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let rigNode = SCNNode()
    /// Marker dots live directly under the rig: the anatomy pieces load at
    /// identity (pre-normalized), and rigNode children take normalized-space
    /// coordinates directly while still rotating with the body.
    let marksNode = SCNNode()
    let muscleNode = SCNNode()   // muscle children — hidden at rest, revealed on tap
    let skinNode = SCNNode()     // skin shell — visible + opaque at rest, fades on reveal
    let style: BodyModelStyle

    /// every mapped piece, for O(1) candidate-highlight + hit-test reverse lookup.
    private var nodesByName: [String: SCNNode] = [:]

    private(set) var loadFailed = false
    /// True once the (possibly cached) body mesh has been attached to
    /// `rigNode`. `BodySceneView` shows a placeholder until this flips.
    private(set) var isLoaded = false

    /// Current committed rotation (radians) — updated as the user drags / the
    /// facing picker snaps. Kept here (not just on the node) so gesture deltas
    /// can be applied relative to the last committed value.
    var committedRotationY: CGFloat = 0

    init(style: BodyModelStyle = .anatomy) {
        self.style = style
        setUpCamera()
        setUpLights()
        scene.rootNode.addChildNode(rigNode)
        rigNode.addChildNode(marksNode)
        rigNode.addChildNode(muscleNode)
        rigNode.addChildNode(skinNode)
        // Muscle layer starts hidden + fully transparent — isHidden excludes it
        // from hit-testing, and opacity 0 means it doesn't flash full-strength
        // the instant `loadIfNeeded` unhides it for a reveal.
        muscleNode.isHidden = true
        muscleNode.opacity = 0
        // Mesh loading is kicked off asynchronously by BodySceneView (see
        // `loadIfNeeded`) instead of here — parsing the OBJ is too heavy to
        // do synchronously on the main thread during View init.
    }

    /// Base camera distance for the (height-normalised-to-2.0) body.
    static let defaultCameraDistance: CGFloat = 2.28

    /// Default framing — pulled ~18% back from the base distance so the
    /// model doesn't crowd the frame / floating tab bar.
    static let freeExploreCameraDistance: CGFloat = defaultCameraDistance * 1.18

    private func setUpCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.1
        camera.zFar = 20
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, Float(BodyRig.defaultCameraDistance))
        scene.rootNode.addChildNode(cameraNode)
    }

    private func setUpLights() {
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1000
        key.color = UIColor.white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(3, 4, 5)
        keyNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 380
        fill.color = UIColor.white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-3, 1, 4)
        fillNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 260
        rim.color = UIColor.white
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(0, 2, -5)
        rimNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 180
        ambient.color = UIColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    /// Parses the skin+muscle mesh (background) and attaches one node per piece
    /// with a base material; muscle pieces go under `muscleNode` (grayscale),
    /// the skin piece under `skinNode` (soft neutral skin tone). Idempotent.
    @MainActor
    func loadIfNeeded() async {
        guard !isLoaded, !loadFailed else { return }
        guard let parts = await BodyMeshLoader.shared.anatomyParts() else { loadFailed = true; return }
        for part in parts {
            let geometry = SCNGeometry(sources: part.sources, elements: [part.element])
            let isSkin = part.layer == "skin"
            geometry.materials = [isSkin ? Self.makeSkinMaterial() : Self.makeBaseMaterial()]
            let node = SCNNode(geometry: geometry)
            node.name = part.name
            (isSkin ? skinNode : muscleNode).addChildNode(node)
            nodesByName[part.name] = node
        }
        isLoaded = true
    }

    private static func makeBaseMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        m.metalness.contents = 0.0
        m.roughness.contents = 0.6
        m.diffuse.contents = MuscleHighlight.baseTone
        return m
    }

    private static func makeSkinMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.isDoubleSided = true
        m.metalness.contents = 0.0
        m.roughness.contents = 0.75
        m.diffuse.contents = MuscleHighlight.skinTone
        return m
    }

    /// Reveals the muscle layer under the skin: unhides `muscleNode` immediately
    /// (so it can render at 0 opacity instead of flashing full-strength), then
    /// animates it in as `skinNode` fades to a translucent scrim, then colorizes
    /// the disambiguation candidates. Mirrors the pre-anatomy-model app's
    /// skin/muscle reveal, adapted to the single-OBJ per-node loader.
    func reveal(_ candidates: [MarkCandidate], focused: String?) {
        muscleNode.isHidden = false
        SCNTransaction.begin()
        SCNTransaction.animationDuration = MuscleHighlight.revealDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        muscleNode.opacity = 1
        skinNode.opacity = MuscleHighlight.skinRevealedOpacity
        SCNTransaction.commit()
        showCandidates(candidates, focused: focused)
    }

    /// Restores the opaque skin and hides the muscle layer again once the fade
    /// completes (so taps go back to hitting only the skin), and resets
    /// every muscle piece's tint.
    func dismissReveal() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = MuscleHighlight.revealDuration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        muscleNode.opacity = 0
        skinNode.opacity = 1
        SCNTransaction.completionBlock = { [weak self] in
            self?.muscleNode.isHidden = true
        }
        SCNTransaction.commit()
        resetTints()
    }

    // MARK: - Marker dots

    /// Renders the single "you tapped here" dot, or clears it when `nil`.
    /// One neutral accent dot, no sensation colour, and never more than one
    /// at a time.
    func updateSelection(point: SIMD3<Float>?) {
        marksNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let point else { return }
        let sphere = SCNSphere(radius: 0.028)
        let color = UIColor(Color.luminaPrimary)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        sphere.materials = [material]
        let node = SCNNode(geometry: sphere)
        node.name = "selection-dot"
        node.position = SCNVector3(point.x, point.y, point.z)
        marksNode.addChildNode(node)
    }

    /// Debug: launch with `-debugHitboxes YES` to render every hit volume as
    /// a translucent box over the skin — verifies box↔mesh alignment and the
    /// anatomical L/R relabel (at front view, "Left Biceps" must sit on the
    /// VIEWER'S RIGHT).
    func addDebugHitboxesIfEnabled() {
        guard UserDefaults.standard.bool(forKey: "debugHitboxes") else { return }
        for volume in BodyHitVolumes.all {
            let size = volume.maxBound - volume.minBound
            let box = SCNBox(width: CGFloat(size.x), height: CGFloat(size.y),
                             length: CGFloat(size.z), chamferRadius: 0)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.18)
            material.isDoubleSided = true
            box.materials = [material]
            let node = SCNNode(geometry: box)
            node.name = volume.name
            node.position = SCNVector3(volume.center.x, volume.center.y, volume.center.z)
            rigNode.addChildNode(node)
        }
    }

    // MARK: - Rotation math

    /// Signed shortest angular distance from `from` to `to`, wrapped to ±π —
    /// so a turn never takes the long way round the seam.
    static func shortestDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        let twoPi = 2 * CGFloat.pi
        var delta = (to - from.truncatingRemainder(dividingBy: twoPi))
            .truncatingRemainder(dividingBy: twoPi)
        if delta >  .pi { delta -= twoPi }
        if delta < -.pi { delta += twoPi }
        return delta
    }

    /// The absolute rig Y-rotation that brings `localPoint` round to face the
    /// camera (which sits on world +Z).
    ///
    /// `localPoint` is rigNode-LOCAL, so the rig's current rotation is already
    /// factored out and the target is simply the negated bearing —
    /// independent of `currentY`. `currentY` is used only to decide whether
    /// the move is worth making.
    ///
    /// Returns `nil` when the point has no bearing (it sits on the Y axis) or
    /// when the rig already faces it to within `threshold`, so a tap near
    /// dead-centre is a no-op rather than a jitter.
    static func rotationToFace(localPoint: SIMD3<Float>,
                               currentY: CGFloat,
                               threshold: CGFloat = 8 * .pi / 180) -> CGFloat? {
        let planar = SIMD2<Float>(localPoint.x, localPoint.z)
        guard simd_length(planar) > 1e-4 else { return nil }
        let target = -CGFloat(atan2(localPoint.x, localPoint.z))
        guard abs(shortestDelta(from: currentY, to: target)) >= threshold else { return nil }
        return target
    }

    // MARK: - Rotation

    func applyDragRotation(deltaX: CGFloat) {
        let radiansPerPoint: CGFloat = 0.012
        rigNode.eulerAngles.y = Float(committedRotationY + deltaX * radiansPerPoint)
    }

    func commitDragRotation(deltaX: CGFloat) {
        let radiansPerPoint: CGFloat = 0.012
        committedRotationY += deltaX * radiansPerPoint
        rigNode.eulerAngles.y = Float(committedRotationY)
    }

    // MARK: - Disambiguation focus

    /// Dollies the camera to frame `localPoint` (rigNode-local, normalized
    /// model space) close-up and centered — the double-tap zoom onto the
    /// actual tapped dot. The camera approaches along the dot's **outward
    /// radial-horizontal normal** (the direction from the body's central Y
    /// axis out through the dot) rather than a fixed world-Z, so a dot on the
    /// side/back of a rotated limb is framed head-on instead of edge-on or
    /// occluded. The rig isn't rotated — callers freeze the rotation gesture
    /// while focused, since this camera pose is computed for the rig
    /// orientation at the moment of the call.
    func focus(on localPoint: SIMD3<Float>, duration: TimeInterval = 0.5, completion: @escaping () -> Void = {}) {
        let worldV = rigNode.convertPosition(SCNVector3(localPoint.x, localPoint.y, localPoint.z), to: nil)
        let world = SIMD3<Float>(Float(worldV.x), Float(worldV.y), Float(worldV.z))
        let distance = Float(BodyRig.defaultCameraDistance) * 0.55

        // Outward horizontal direction from the central axis (x=0,z=0) to the
        // dot. Degenerate only if the dot sits exactly on the axis — fall back
        // to a front-on view then.
        let horizontal = SIMD3<Float>(world.x, 0, world.z)
        let outward = simd_length(horizontal) > 1e-4
            ? simd_normalize(horizontal)
            : SIMD3<Float>(0, 0, 1)

        // Camera sits out along the normal, lifted slightly so it looks a touch
        // down onto the point rather than dead level.
        let camPos = world + outward * distance + SIMD3<Float>(0, 0.06, 0)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = SCNVector3(camPos.x, camPos.y, camPos.z)
        // `look(at:)` uses the world up-vector (0,1,0), so the camera never rolls
        // around its view axis — focus stays a pure upright dolly (pinned by
        // BodyRigFocusTests). Any apparent turn on select is dolly parallax (the
        // dot is framed from its own outward normal), not a rig/camera rotation.
        cameraNode.look(at: SCNVector3(world.x, world.y, world.z))
        SCNTransaction.completionBlock = completion
        SCNTransaction.commit()
    }

    // MARK: - Candidate region highlights

    /// Highlights each disambiguation candidate on the real muscle mesh, colour-
    /// coded by index (matching the side-rail labels). Each candidate's muscle
    /// node(s) get a **light tint** (base anatomical shading lerped toward the
    /// accent — subtle for unfocused, stronger for focused) plus an **emission
    /// glow** that lifts the focused candidate, so adjacent heads stay distinct.
    /// Candidates with no muscle geometry (face zones, joints) fall back to a
    /// small accent dot at their anchor. Idempotent — resets prior tints first.
    func showCandidates(_ candidates: [MarkCandidate], focused: String?) {
        resetTints()
        for (i, c) in candidates.enumerated() {
            let isFocused = c.name == focused
            let accent = CandidatePalette.uiColor(i)
            let names = MuscleNodeNames.nodeNames(forRegion: c.name)
            if names.isEmpty {
                addCandidateDot(for: c, accent: accent, focused: isFocused)
            } else {
                for n in names { if let node = nodesByName[n] { applyTint(accent, focused: isFocused, to: node) } }
            }
        }
    }

    /// Restores every muscle piece to its neutral base tone and removes any
    /// transient candidate dots (face-zone fallbacks with no geometry). Leaves
    /// the skin node's single tone untouched (it never gets tinted).
    private func resetTints() {
        for node in nodesByName.values where node.parent === muscleNode {
            guard let m = node.geometry?.firstMaterial else { continue }
            m.diffuse.contents = MuscleHighlight.baseTone
            m.emission.intensity = 0
        }
        muscleNode.childNodes.filter { $0.name?.hasPrefix("cand-dot:") == true }.forEach { $0.removeFromParentNode() }
    }

    /// Tints one node toward `accent`; `focused` deepens the tint and glow.
    private func applyTint(_ accent: UIColor, focused: Bool, to node: SCNNode) {
        guard let m = node.geometry?.firstMaterial else { return }
        let tint = focused ? MuscleHighlight.focusedTint : MuscleHighlight.unfocusedTint
        m.diffuse.contents = MuscleHighlight.lerp(MuscleHighlight.baseTone, accent, tint)
        m.emission.contents = accent
        m.emission.intensity = focused ? MuscleHighlight.focusedGlow : MuscleHighlight.unfocusedGlow
    }

    /// On-body accent dot for a candidate with no mapped geometry (should be rare
    /// now that joints/face zones resolve to real nodes).
    private func addCandidateDot(for c: MarkCandidate, accent: UIColor, focused: Bool) {
        let sphere = SCNSphere(radius: CGFloat(focused ? 0.028 : 0.022))
        let m = SCNMaterial()
        m.diffuse.contents = accent
        m.emission.contents = accent
        m.emission.intensity = focused ? 0.6 : 0.35
        m.readsFromDepthBuffer = false
        m.writesToDepthBuffer = false
        sphere.materials = [m]
        let node = SCNNode(geometry: sphere)
        node.name = "cand-dot:\(c.name)"
        node.position = SCNVector3(c.point.x, c.point.y, c.point.z)
        node.renderingOrder = focused ? 21 : 20
        muscleNode.addChildNode(node)
    }

    /// Restores the camera to a plain forward-facing shot at `distance` —
    /// used when disambiguation is cancelled or resolved.
    ///
    /// `focus()` deliberately dollies off the Z-axis, out along the tapped
    /// dot's outward normal (see its doc comment). Snapping straight back to
    /// (0,0,distance) in one animated beat swings the camera through that
    /// same arc in reverse — which orbits the body and reads as the FIGURE
    /// rotating, not the camera zooming out (the exact illusion `focus()`
    /// guards against, unguarded on the way back). Retreating along the
    /// current bearing first removes the orbit — the dot just recedes — then
    /// the bearing snaps to dead-center instantly, once the camera is far
    /// enough out for that jump to be imperceptible.
    func resetCamera(distance: CGFloat, duration: TimeInterval = 0.4) {
        let receded = BodyRig.recededPosition(from: cameraNode.position, minDistance: distance)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cameraNode.position = receded
        cameraNode.look(at: SCNVector3(0, 0, 0))
        SCNTransaction.completionBlock = { [weak self] in
            guard let self else { return }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0
            self.cameraNode.position = SCNVector3(0, 0, Float(distance))
            self.cameraNode.look(at: SCNVector3(0, 0, 0))
            SCNTransaction.commit()
        }
        SCNTransaction.commit()
    }

    /// Pure helper for `resetCamera`'s first phase: moves `position` straight
    /// out along its own bearing (the horizontal direction from the origin
    /// through it) to at least `minDistance`, preserving whatever azimuth the
    /// focus dolly left the camera at. Degenerate only if the camera sits
    /// exactly on the Y axis — falls back to the canonical +Z bearing then.
    static func recededPosition(from position: SCNVector3, minDistance: CGFloat) -> SCNVector3 {
        let current = SIMD3<Float>(Float(position.x), 0, Float(position.z))
        let bearing = simd_length(current) > 1e-4 ? simd_normalize(current) : SIMD3<Float>(0, 0, 1)
        let target = bearing * Float(max(defaultCameraDistance, minDistance))
        return SCNVector3(target.x, 0, target.z)
    }

    /// Snap to the nearest equivalent of `target` (0 = front, π = back) via the
    /// shortest angular path, so flipping Front/Back never spins the long way round.
    func snap(to target: CGFloat) {
        let current = committedRotationY
        let destination = current + BodyRig.shortestDelta(from: current, to: target)

        // Eager, not deferred to the completion block: applyDragRotation /
        // commitDragRotation compose against committedRotationY synchronously,
        // so if this snap is mid-animation when a drag starts, the stored
        // bearing must already read as `destination` (where the rig is
        // heading) or the drag composes against a stale pre-snap value and
        // the body visibly jumps. Do not move this back into completionBlock.
        committedRotationY = destination
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        rigNode.eulerAngles.y = Float(destination)
        SCNTransaction.commit()
    }
}

// MARK: - SceneKit host

/// SwiftUI's SceneView hides its SCNView, which we need for hitTest — so the
/// scene is hosted directly. SwiftUI drag/magnify gestures still attach on
/// top; the tap recognizer fails automatically once a pan starts.
private struct SceneKitContainer: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode
    /// Every tap — on the body or off it — comes through here as one
    /// recognizer; `resolveRegion`'s hit/miss decides what it means upstream.
    /// A single recognizer sidesteps the old double-tap dance entirely (no
    /// `require(toFail:)` delay, no mutual-exclusion delegate juggling).
    var onSingleTap: ((CGPoint, SCNView) -> Void)?
    /// Fired once after the SCNView is created — lets BodySceneView hold a
    /// reference for `projectPoint` (candidate-pin placement), since
    /// SwiftUI's SceneView hides the underlying SCNView entirely.
    var onViewReady: ((SCNView) -> Void)?

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear

        let single = UITapGestureRecognizer(target: context.coordinator,
                                            action: #selector(Coordinator.handleSingleTap(_:)))
        single.numberOfTapsRequired = 1
        view.addGestureRecognizer(single)

        DispatchQueue.main.async { onViewReady?(view) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        // A covered SCNView pauses its display link; re-assert continuous
        // rendering so it resumes drawing when revealed (e.g. after popping the
        // exercise list) instead of showing a stale/blank frame.
        view.rendersContinuously = true
        view.isPlaying = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    final class Coordinator: NSObject {
        var onSingleTap: ((CGPoint, SCNView) -> Void)?

        init(onSingleTap: ((CGPoint, SCNView) -> Void)?) {
            self.onSingleTap = onSingleTap
        }

        @objc func handleSingleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? SCNView else { return }
            onSingleTap?(recognizer.location(in: view), view)
        }
    }
}

// MARK: - Body Scene View

private extension BodyFacing {
    /// Rig Y-rotation for this facing (0 = front, π = back).
    var rotationY: CGFloat { self == .front ? 0 : .pi }
}

/// A muscle region offered by the double-tap muscle-selection overlay, with
/// the rigNode-local point its label/leader anchors to (its hitbox center)
/// and the box bounds used to draw the "rough" on-body region highlight.
struct MarkCandidate: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let point: SIMD3<Float>
    var minBound: SIMD3<Float> = .zero
    var maxBound: SIMD3<Float> = .zero
}

/// Deterministic colour per candidate index — cool hues group the heads of one
/// muscle as "one muscle, subdivided"; used identically by the on-body
/// highlight boxes (SceneKit) and the side-rail labels (SwiftUI) so a colour
/// dot on a label matches its region on the body.
enum CandidatePalette {
    // Mid-tone versions of the app's pastels (seperate-main): soft enough to
    // sit with the black + pastel look, strong enough to still tint the
    // grey muscle layer visibly (full pastels wash out against it).
    static let colors: [Color] = [
        Color(red: 0.56, green: 0.69, blue: 0.92),   // pastel blue
        Color(red: 0.55, green: 0.80, blue: 0.62),   // pastel mint
        Color(red: 0.71, green: 0.63, blue: 0.93),   // pastel lavender
        Color(red: 0.94, green: 0.66, blue: 0.47),   // pastel peach (neighbour muscle)
    ]
    static func color(_ i: Int) -> Color { colors[((i % colors.count) + colors.count) % colors.count] }
    static func uiColor(_ i: Int) -> UIColor { UIColor(color(i)) }
}

struct BodySceneView: View {
    let facing: BodyFacing

    /// Which anatomy layer to render. `.anatomy` is the only style.
    var style: BodyModelStyle = .anatomy

    /// The point the user last single-tapped, rendered as one neutral dot.
    var selectionPoint: SIMD3<Float>? = nil

    /// A tap that resolved a region: the body has already been rotated to
    /// face it by the time this fires, and it always opens the muscle
    /// picker. Rotation stays free — hit-testing works at any camera angle.
    var onRegionDrilled: ((String, SIMD3<Float>) -> Void)? = nil
    /// A tap whose raycast resolved nothing (off the mesh, or on a spot no
    /// hit volume covers) — "outside" the body. Fires in every state (idle,
    /// selected, or focused on the muscle picker); the parent decides what
    /// "outside" backs out of.
    var onBackgroundTap: (() -> Void)? = nil

    /// Non-empty while showing the muscle-picker disambiguation popup: a tap
    /// that resolves to more than one candidate zooms the camera to the
    /// first candidate and places a labeled pin for each. Rotation/zoom
    /// gestures freeze while this is non-empty, since the camera is under
    /// programmatic control and pin positions aren't recomputed per-frame.
    var disambiguationCandidates: [MarkCandidate] = []
    /// The tapped dot to zoom onto (rigNode-local). When nil, falls back to the
    /// primary candidate's anchor for backward compatibility. Stays set after
    /// the picker closes (candidates go empty) so the camera stays framed on
    /// it — only clearing this fully zooms back out.
    var focusPoint: SIMD3<Float>? = nil
    /// Which candidate is currently highlighted (its box brightened). Owned by
    /// the parent so it survives navigation (Back returns to the same focus).
    var focusedRegion: String? = nil
    /// A tap on an unfocused candidate (region box or side label) → focus it.
    var onCandidateFocused: ((String) -> Void)? = nil
    /// A tap on the already-focused candidate → drill into its exercises.
    var onCandidateSelected: ((String) -> Void)? = nil
    /// Bumped by the parent when returning from the pushed exercise list, to
    /// re-apply the zoom + re-project the labels: a covered SCNView pauses
    /// rendering and its projected anchors go stale, so the scene must be
    /// re-driven when it becomes visible again (Phase C back-restores-zoom).
    var refocusToken: Int = 0

    @State private var rig: BodyRig
    @State private var dragActive = false
    @State private var cameraZ: CGFloat
    @State private var committedCameraZ: CGFloat
    /// Mirrors `rig.isLoaded`/`rig.loadFailed` in @State so SwiftUI actually
    /// re-renders once the background OBJ parse finishes — `rig` is a class,
    /// so mutating its stored properties alone wouldn't invalidate the view.
    @State private var isLoading = true
    @State private var scnView: SCNView?
    @State private var pinPositions: [String: CGPoint] = [:]
    /// Set once the initial `facing`-driven rotation snap has happened.
    /// `.onAppear` fires again when this view reappears after the exercise
    /// list is popped — without this guard that re-snap would throw away a
    /// tap-to-face rotation the single-tap path just set (see `handleSingleTap`),
    /// spinning the body back to `facing.rotationY` even though nothing asked
    /// it to. `.onChange(of: facing)` already owns every later facing change
    /// (the Front/Back toggle), so this flag only needs to gate the one-time
    /// initial snap.
    @State private var didSnapInitialFacing = false
    @Environment(\.colorScheme) private var colorScheme

    private let minCameraZ: CGFloat = BodyRig.defaultCameraDistance * 0.62         // closer  = zoomed in
    private let maxCameraZ: CGFloat = BodyRig.freeExploreCameraDistance * 1.25      // farther = zoomed out

    private var isFocused: Bool { !disambiguationCandidates.isEmpty }

    init(facing: BodyFacing,
         style: BodyModelStyle = .anatomy,
         selectionPoint: SIMD3<Float>? = nil,
         onRegionDrilled: ((String, SIMD3<Float>) -> Void)? = nil,
         onBackgroundTap: (() -> Void)? = nil,
         disambiguationCandidates: [MarkCandidate] = [],
         focusPoint: SIMD3<Float>? = nil,
         focusedRegion: String? = nil,
         onCandidateFocused: ((String) -> Void)? = nil,
         onCandidateSelected: ((String) -> Void)? = nil,
         refocusToken: Int = 0) {
        self.facing = facing
        self.style = style
        self.selectionPoint = selectionPoint
        self.onRegionDrilled = onRegionDrilled
        self.onBackgroundTap = onBackgroundTap
        self.disambiguationCandidates = disambiguationCandidates
        self.focusPoint = focusPoint
        self.focusedRegion = focusedRegion
        self.onCandidateFocused = onCandidateFocused
        self.onCandidateSelected = onCandidateSelected
        self.refocusToken = refocusToken
        _rig = State(initialValue: BodyRig(style: style))
        _cameraZ = State(initialValue: BodyRig.freeExploreCameraDistance)
        _committedCameraZ = State(initialValue: BodyRig.freeExploreCameraDistance)
    }

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading 3D model…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rig.loadFailed {
                ContentUnavailableView(
                    "3D Model Unavailable",
                    systemImage: "figure.stand",
                    description: Text("The body model couldn't be loaded.")
                )
            } else {
                SceneKitContainer(scene: rig.scene, pointOfView: rig.cameraNode,
                                  onSingleTap: singleTapHandler,
                                  onViewReady: { scnView = $0 })
                    .gesture(rotationGesture, including: isFocused ? .none : .all)
                    .simultaneousGesture(zoomGesture, including: isFocused ? .none : .all)
                    .overlay(alignment: .top) {
                        Text("Tap a sore spot for muscles · drag to rotate")
                            .font(.luminaCaption.weight(.medium))
                            .foregroundStyle(Color.luminaOnSurfaceVariant)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.luminaCardFill, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.luminaHairline, lineWidth: 0.5))
                            .padding(.top, 6)
                            .opacity(dragActive || isFocused ? 0 : 0.85)
                            .animation(.easeInOut(duration: 0.2), value: dragActive)
                    }
                    .overlay {
                        if isFocused {
                            CandidateRailOverlay(
                                candidates: disambiguationCandidates,
                                anchors: pinPositions,
                                focusedRegion: focusedRegion,
                                onTap: handleCandidateTap
                            )
                            .transition(.opacity)
                        }
                    }
            }
        }
        .onAppear {
            // Skip while disambiguating: the view also disappears/reappears
            // when the exercise list is pushed/popped over it, and in that
            // case `refocusToken` (below) owns the camera — it redoes the
            // full off-axis dolly + look(at:). Stomping just `position.z`
            // here would leave the camera's x/y and orientation mismatched,
            // which reads as the body having rotated.
            guard !isFocused else { return }
            if !didSnapInitialFacing {
                rig.snap(to: facing.rotationY)
                didSnapInitialFacing = true
            }
            rig.cameraNode.position.z = Float(cameraZ)
        }
        .task(id: ObjectIdentifier(rig)) {
            // Off the main thread inside BodyMeshLoader; hops back to the
            // main actor only to attach the finished node. `id:` re-runs this
            // if `rig` itself is ever replaced (it currently isn't post-init,
            // but keeps this correct if that changes).
            await rig.loadIfNeeded()
            rig.updateSelection(point: selectionPoint)
            rig.addDebugHitboxesIfEnabled()
            isLoading = false
        }
        .onChange(of: facing) { _, newFacing in
            rig.snap(to: newFacing.rotationY)
        }
        .onChange(of: disambiguationCandidates) { _, newCandidates in
            guard !newCandidates.isEmpty else {
                pinPositions = [:]
                rig.dismissReveal()
                // If the parent kept `focusPoint` set, this is just the
                // picker closing back to the zoomed region view — leave the
                // camera where it is. Only a full clear (both go empty/nil
                // together) backs the camera out.
                if focusPoint == nil {
                    rig.resetCamera(distance: cameraZ)
                }
                return
            }
            applyFocus(for: newCandidates)
        }
        .onChange(of: focusedRegion) { _, newFocus in
            // Re-tint the muscle highlight when the focused candidate changes;
            // camera stays put (the dot is still the frame subject).
            guard !disambiguationCandidates.isEmpty else { return }
            rig.showCandidates(disambiguationCandidates,
                               focused: newFocus ?? disambiguationCandidates.first?.name)
        }
        .onChange(of: refocusToken) { _, _ in
            // Returned from the exercise list — re-drive the paused SCNView and
            // recompute the (now-stale) projected label anchors.
            guard !disambiguationCandidates.isEmpty else { return }
            applyFocus(for: disambiguationCandidates)
        }
        .onChange(of: selectionPoint) { _, newPoint in
            rig.updateSelection(point: newPoint)
        }
        .onAppear { applyBackground() }
        .onChange(of: colorScheme) { _, _ in applyBackground() }
    }

    /// SCNScene renders opaque white behind the mesh by default, which reads
    /// as a jarring flash of light content in dark mode — so this keys the
    /// scene background to the same dynamic surface colour as the rest of
    /// the screen and re-applies it whenever the app's colour scheme flips.
    private func applyBackground() {
        let trait = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        rig.scene.background.contents = UIColor(Color.luminaSurface).resolvedColor(with: trait)
    }

    // MARK: - Tap → region resolution

    /// While focused (the muscle picker), taps hit-test the revealed muscle
    /// mesh so tapping a highlighted muscle selects it directly. Otherwise a
    /// tap turns the body to face the point and drills straight into the
    /// muscle picker — there's only one "in" gesture now.
    private var singleTapHandler: ((CGPoint, SCNView) -> Void)? {
        if isFocused {
            return { point, view in handleCandidateHitTest(at: point, in: view) }
        }
        guard onRegionDrilled != nil || onBackgroundTap != nil else { return nil }
        return { point, view in handleSingleTap(at: point, in: view) }
    }

    /// A tap on the body: turn to face the tapped point, then drill into the
    /// muscle picker. `rotationToFace` returns nil when the rig already faces
    /// it, which is the common case for a tap on the side already showing.
    /// A tap that misses the mesh entirely is "outside" the body instead.
    private func handleSingleTap(at point: CGPoint, in view: SCNView) {
        guard let (region, local) = resolveRegion(at: point, in: view) else {
            handleOutsideTap()
            return
        }
        if let target = BodyRig.rotationToFace(localPoint: local,
                                               currentY: rig.committedRotationY) {
            rig.snap(to: target)
        }
        onRegionDrilled?(region, local)
    }

    /// Raycasts the revealed muscle geometry; the nearest hit whose muscle node
    /// (or face-zone fallback dot) maps to one of the CURRENT candidates routes
    /// to the focus/select decision. Skin hits are skipped (they map to nothing),
    /// so tapping the translucent skin over a candidate still selects the muscle.
    private func handleCandidateHitTest(at point: CGPoint, in view: SCNView) {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue as NSNumber])
        // A tap that misses the mesh ENTIRELY (no hits at all — not even
        // skin) is "outside" the body, same as at rest: with only one tap
        // recognizer now, this is the only place that can catch it while the
        // picker is up. A tap that lands ON the mesh but matches no
        // candidate (the loop below falls through) is a fumbled tap on
        // empty skin, not a deliberate "get me out" — left alone.
        guard !hits.isEmpty else {
            handleOutsideTap()
            return
        }
        let candidateNames = Set(disambiguationCandidates.map(\.name))
        for hit in hits {
            guard let nodeName = hit.node.name else { continue }
            if nodeName.hasPrefix("cand-dot:") {
                let name = String(nodeName.dropFirst("cand-dot:".count))
                if candidateNames.contains(name) { handleCandidateTap(name); return }
            } else if let match = MuscleNodeNames.matchingCandidate(forNode: nodeName,
                                                                    among: candidateNames) {
                handleCandidateTap(match)
                return
            }
        }
    }

    /// First tap on a candidate focuses/highlights it; a second tap on the
    /// already-focused candidate drills into its exercises. Shared by the
    /// on-body region boxes and the side-rail labels.
    private func handleCandidateTap(_ name: String) {
        if focusedRegion == name {
            onCandidateSelected?(name)
        } else {
            onCandidateFocused?(name)
        }
    }

    /// Zooms onto the tapped dot and reveals the muscle layer — fading the skin
    /// to a translucent scrim while the muscle mesh fades in and each candidate
    /// colorizes; projects the label anchors once the dolly settles. Shared by
    /// the initial double-tap and the return-from-navigation re-focus.
    private func applyFocus(for candidates: [MarkCandidate]) {
        guard let primary = candidates.first else { return }
        rig.focus(on: focusPoint ?? primary.point) { projectPinPositions(for: candidates) }
        rig.reveal(candidates, focused: focusedRegion ?? primary.name)
    }

    /// Re-projects each candidate's rigNode-local anchor to on-screen points
    /// via `SCNView.projectPoint`, once the focus dolly animation completes
    /// (camera + rig are static then, so a single projection stays correct
    /// for as long as the popup is showing).
    private func projectPinPositions(for candidates: [MarkCandidate]) {
        guard let scnView else { return }
        var positions: [String: CGPoint] = [:]
        for candidate in candidates {
            let world = rig.rigNode.convertPosition(
                SCNVector3(candidate.point.x, candidate.point.y, candidate.point.z), to: nil)
            let projected = scnView.projectPoint(world)
            positions[candidate.name] = CGPoint(x: CGFloat(projected.x), y: CGFloat(projected.y))
        }
        withAnimation(.easeIn(duration: 0.2)) {
            pinPositions = positions
        }
    }

    /// A tap "outside" the body: `resolveRegion` already found no hit at the
    /// tap location (a tap that lands on the mesh — including the selection
    /// dot or a candidate pin — isn't "outside").
    ///
    /// Fires in EVERY state, including fully at rest (no selection, no
    /// picker) — a quick way to reset any prior pinch back to a framing that
    /// shows the whole body, not just a way to back out of something.
    ///
    /// While the muscle picker is up, the parent's `onBackgroundTap` closes
    /// it but keeps `focusPoint` set (landing back on the zoomed region
    /// view), so `disambiguationCandidates`'s `onChange` below leaves the
    /// camera alone — nothing more to do here. Only once the parent also
    /// drops `focusPoint` (a second outside tap, from that zoomed resting
    /// state) is there no such `onChange` to piggyback on, so this resets the
    /// camera itself: back to the free-explore framing, so the whole body is
    /// visible again regardless of any prior pinch or zoom.
    private func handleOutsideTap() {
        if !isFocused {
            cameraZ = BodyRig.freeExploreCameraDistance
            committedCameraZ = cameraZ
            rig.resetCamera(distance: cameraZ)
        }
        onBackgroundTap?()
    }

    /// Stage 1: raycast the visible skin surface — the only unhidden geometry
    /// at rest (the selection dot is excluded explicitly, so the first
    /// non-marker hit is the skin surface point). Stage 2: convert the world
    /// hit point to rigNode-local (normalized model space, rotation factored
    /// out) and resolve it with pure math.
    private func resolveRegion(at point: CGPoint, in view: SCNView) -> (String, SIMD3<Float>)? {
        let hits = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue as NSNumber])
        guard let hit = hits.first(where: { !isMarkerNode($0.node) }) else { return nil }
        let local = rig.rigNode.convertPosition(hit.worldCoordinates, from: nil)
        let normalized = SIMD3(Float(local.x), Float(local.y), Float(local.z))
        guard let region = MuscleHitResolver.regionName(at: normalized, in: BodyHitVolumes.all) else {
            return nil
        }
        return (region, normalized)
    }

    private func isMarkerNode(_ node: SCNNode) -> Bool {
        sequence(first: node, next: \.parent).contains(rig.marksNode)
    }

    // MARK: - Gestures

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                dragActive = true
                rig.applyDragRotation(deltaX: value.translation.width)
            }
            .onEnded { value in
                dragActive = false
                rig.commitDragRotation(deltaX: value.translation.width)
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // magnification > 1 = pinch out (zoom in) -> move camera closer.
                let proposed = committedCameraZ / value.magnification
                cameraZ = min(max(proposed, minCameraZ), maxCameraZ)
                rig.cameraNode.position.z = Float(cameraZ)
            }
            .onEnded { _ in
                committedCameraZ = cameraZ
            }
    }
}

// MARK: - Candidate rail overlay

/// The disambiguation labels, pushed to whichever screen edge has more room
/// (away from the dot's cluster), each larger than the old on-body capsules and
/// connected to its muscle region by a thin leader line. The label's colour dot
/// matches its on-body highlight box. Tapping a label focuses that region;
/// tapping the focused one again drills into its exercises.
private struct CandidateRailOverlay: View {
    let candidates: [MarkCandidate]
    let anchors: [String: CGPoint]
    let focusedRegion: String?
    let onTap: (String) -> Void

    private let labelWidth: CGFloat = 164
    private let rowGap: CGFloat = 54
    private let edgeInset: CGFloat = 86

    private struct Placement: Identifiable {
        var id: String { name }
        let name: String
        let index: Int
        var center: CGPoint
        var leaderStart: CGPoint
    }

    var body: some View {
        GeometryReader { geo in
            let placements = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for p in placements {
                        guard let anchor = anchors[p.name] else { continue }
                        let focused = p.name == focusedRegion
                        var path = Path()
                        path.move(to: p.leaderStart)
                        path.addLine(to: anchor)
                        ctx.stroke(path,
                                   with: .color(CandidatePalette.color(p.index).opacity(focused ? 0.95 : 0.5)),
                                   style: StrokeStyle(lineWidth: focused ? 1.7 : 1.2,
                                                      dash: focused ? [] : [2, 3]))
                        let r: CGFloat = focused ? 5 : 3.5
                        ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - r, y: anchor.y - r,
                                                        width: r * 2, height: r * 2)),
                                 with: .color(CandidatePalette.color(p.index)))
                    }
                }
                .allowsHitTesting(false)   // let taps fall through to the 3D boxes

                ForEach(placements) { p in
                    label(for: p).position(p.center)
                }
            }
        }
    }

    /// Graphite chip with the candidate's color dot; the focused one fills
    /// with its color (ink text) and shows an arrow — tap again to open.
    private func label(for p: Placement) -> some View {
        let focused = p.name == focusedRegion
        let color = CandidatePalette.color(p.index)
        let shape = RoundedRectangle(cornerRadius: LuminaRadius.control, style: .continuous)
        return Button { onTap(p.name) } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(focused ? Color.onPastel.opacity(0.85) : color)
                    .frame(width: 9, height: 9)
                Text(p.name)
                    .font(.luminaSubheadline.weight(.semibold))
                    .foregroundStyle(focused ? Color.onPastel : Color.luminaOnSurface)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if focused {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.onPastel)
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.45), in: Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 12).padding(.trailing, focused ? 7 : 12).padding(.vertical, 9)
            .frame(width: labelWidth, alignment: .leading)
            .background(focused ? color : Color.luminaCardFill, in: shape)
            .overlay(shape.strokeBorder(focused ? Color.clear : Color.luminaHairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
            .animation(.easeInOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(focused ? "\(p.name) — view exercises"
                                    : "\(p.name) — highlight region")
    }

    /// Places labels in a column on the emptier side and spaces them so they
    /// don't overlap, each sitting at (roughly) its anchor's height.
    private func layout(in size: CGSize) -> [Placement] {
        let present = candidates.enumerated().compactMap { i, c -> (Int, MarkCandidate, CGPoint)? in
            anchors[c.name].map { (i, c, $0) }
        }
        guard !present.isEmpty else { return [] }

        let avgX = present.map(\.2.x).reduce(0, +) / CGFloat(present.count)
        let railRight = avgX < size.width / 2
        let centerX = railRight ? size.width - edgeInset : edgeInset

        // Desired Y = anchor Y, then de-overlap top→bottom and clamp to frame.
        let ordered = present.sorted { $0.2.y < $1.2.y }
        var ys: [CGFloat] = []
        var lastY = -CGFloat.greatestFiniteMagnitude
        let topLimit = rowGap / 2 + 8
        for item in ordered {
            var y = max(item.2.y, lastY + rowGap)
            y = max(y, topLimit)
            lastY = y
            ys.append(y)
        }
        // Pull the stack up if it overran the bottom.
        let bottomLimit = size.height - rowGap / 2 - 8
        if let last = ys.last, last > bottomLimit {
            let shift = last - bottomLimit
            ys = ys.map { max(topLimit, $0 - shift) }
        }

        return ordered.enumerated().map { row, item in
            let (index, cand, _) = item
            let cy = ys[row]
            let leaderX = railRight ? centerX - labelWidth / 2 : centerX + labelWidth / 2
            return Placement(name: cand.name, index: index,
                             center: CGPoint(x: centerX, y: cy),
                             leaderStart: CGPoint(x: leaderX, y: cy))
        }
    }
}

// MARK: - Preview

#Preview("Anatomy") {
    BodySceneView(facing: .front, style: .anatomy)
        .frame(height: 520)
}
