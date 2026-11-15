-- Human-readable full source recovered from original VOID HUB encoded loader.
-- Contains all features as preserved on 2026-11-15.
-- This backup is NOT an auto-loader. Do not replace main with it automatically.


local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

print("[VOID HUB V2] Client startup reached")
local Player = Players.LocalPlayer
if not Player then
    warn("[VOID HUB V2] No LocalPlayer: must run on CLIENT / in a LocalScript.")
    return
end
local SCRIPT_ACCESS_WHITELIST = {
    ["kaximbojorge"] = true,
}

local function isAuthorizedHubUser(username)
    local normalized = string.lower(username)
    for allowedUsername, enabled in pairs(SCRIPT_ACCESS_WHITELIST) do
        if enabled == true and type(allowedUsername) == "string" then
            local cleaned = allowedUsername:match("^%s*(.-)%s*$")
            if cleaned and string.lower(cleaned) == normalized then
                return true
            end
        end
    end
    return false
end

print("[VOID HUB ACCESS] Checking username: " .. Player.Name)
if not isAuthorizedHubUser(Player.Name) then
    warn("[VOID HUB ACCESS] Access denied: " .. Player.Name .. " is not in SCRIPT_ACCESS_WHITELIST")
    pcall(function()
        Player:Kick("VOID HUB: You are not whitelisted to use this script.")
    end)
    return -- Exit BEFORE creating GUI, registering listeners, or changing other hub state.
end
print("[VOID HUB ACCESS] Whitelisted user: " .. Player.Name)
print("[VOID HUB V66 CHECK] Access permitted; username=" .. Player.Name .. " userId=" .. tostring(Player.UserId))

local PlayerGui = Player:WaitForChild("PlayerGui")

local old = PlayerGui:FindFirstChild("VoidHubV1") or PlayerGui:FindFirstChild("VOID_HUB")
if old then old:Destroy() end

local DeathTPIsEscaping = false -- Death TP takes precedence over defensive self-return
local AntiTPIntentionalTeleportUntil = 0 -- prevents Anti TP from undoing VOID HUB Bring/INSTA
-- Shared guard: Carry/INSTA/Gymban and the proximity Forcefield must NEVER
-- issue overlapping teleport sequences, which can move our own character.
local SharedTeleportOwner = nil
local SharedTeleportCooldownUntil = 0

local Gui = Instance.new("ScreenGui")
Gui.Name = "VoidHubV1"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.DisplayOrder = 100000
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
-- Keep the newest hub visible even if a later optional feature errors.
-- The intro still covers the unfinished UI until the readiness gate finishes.
Gui.Enabled = true
Gui:SetAttribute("VoidHubBuild", "2026-11-15-startup-repair")
print("[VOID HUB BUILD] New hub booting; never using the old fallback.")
Gui.Parent = PlayerGui

-- Persistence V1: Save fields, ON/OFF toggles, user lists, keybinds and tabs.
-- Use local file storage when supported; otherwise retain same-session state.
local saveHttp = game:GetService("HttpService")
local saveFile = "VoidHubV1_Settings_" .. tostring(Player.UserId) .. ".json"
local saveEnv
pcall(function() saveEnv = type(getgenv) == "function" and getgenv() or _G end)
saveEnv = type(saveEnv) == "table" and saveEnv or _G
local diskSaveAvailable = type(writefile) == "function" and type(readfile) == "function"
local savedUI = {inputs = {}, toggles = {}, misc = {}}
do
    local fromDisk
    if diskSaveAvailable then
        pcall(function()
            local raw = readfile(saveFile)
            if type(raw) == "string" and #raw < 100000 then
                fromDisk = saveHttp:JSONDecode(raw)
            end
        end)
    end
    local data = type(fromDisk) == "table" and fromDisk or saveEnv.__VOIDHUB_SAVE_V1
    if type(data) == "table" then
        savedUI.inputs = type(data.inputs) == "table" and data.inputs or {}
        savedUI.toggles = type(data.toggles) == "table" and data.toggles or {}
        savedUI.misc = type(data.misc) == "table" and data.misc or {}
    end
end
local savedInputs, savedToggles, savedApply = {}, {}, {}
local savedStateGetter
local saveLoading, saveRevision, toggleOrdinal = true, 0, 0
local function toggleValue(text)
    if type(text) ~= "string" then return nil end
    local upper = string.upper(text)
    if upper:match("%f[%w]OFF%f[%W]") then return false end
    if upper:match("%f[%w]ON%f[%W]") then return true end
    return nil
end
local function saveUISettings()
    for _, record in ipairs(savedInputs) do
        if record.box.Parent then
            savedUI.inputs[record.key] = record.box.Text:sub(1, 2048)
        end
    end
    for _, record in ipairs(savedToggles) do
        if record.button.Parent then
            local active = toggleValue(record.button.Text)
            if active ~= nil then savedUI.toggles[record.key] = active end
        end
    end
    if savedStateGetter then
        local state = savedStateGetter()
        savedUI.misc.showWhitelist = state.ShowWhitelist
        savedUI.misc.showBlacklist = state.ShowBlacklist
        savedUI.misc.espBind = state.ESPBind and state.ESPBind.Name or ""
        savedUI.misc.tracersBind = state.TracersBind and state.TracersBind.Name or ""
    end
    saveEnv.__VOIDHUB_SAVE_V1 = savedUI
    if diskSaveAvailable then
        pcall(function() writefile(saveFile, saveHttp:JSONEncode(savedUI)) end)
    end
end
local function queueUISave()
    if saveLoading then return end
    saveRevision += 1
    local revision = saveRevision
    task.delay(0.4, function()
        if revision == saveRevision then saveUISettings() end
    end)
end
local function persistentToggle(button, callback)
    toggleOrdinal += 1
    local id = tostring(toggleOrdinal) .. "/" ..
        (button.Parent and button.Parent.Name or "Root") .. "/" .. button.Name
    savedToggles[#savedToggles+1] = {key = id, button = button, callback = callback}
    button.Activated:Connect(function(...)
        callback(...)
        task.defer(queueUISave)
    end)
end
local function finishPersistentRestore(root)
    local counted = {}
    for _, obj in ipairs(root:GetDescendants()) do
        if obj:IsA("TextBox") then
            local name = (obj.Parent and obj.Parent.Name or "Root") .. "/" .. obj.Name
            counted[name] = (counted[name] or 0) + 1
            local key = name .. "#" .. tostring(counted[name])
            savedInputs[#savedInputs+1] = {key = key, box = obj}
            local value = savedUI.inputs[key]
            if type(value) == "string" then obj.Text = value:sub(1, 2048) end
            obj:GetPropertyChangedSignal("Text"):Connect(queueUISave)
            obj.FocusLost:Connect(queueUISave)
        end
    end
    -- Apply numeric inputs and whitelist before restoring active toggles.
    for _, callback in ipairs(savedApply) do pcall(callback) end
    for _, record in ipairs(savedToggles) do
        if savedUI.toggles[record.key] == true and record.button.Parent
            and toggleValue(record.button.Text) == false then
            pcall(record.callback)
        end
    end
    saveLoading = false
    saveUISettings()
end
Gui.Destroying:Connect(saveUISettings)

print("[VOID HUB V2] ScreenGui created and parented to PlayerGui")

-- Intro fades only AFTER the final feature cards and layout are ready.
local guiFullyLoaded = false


-- VoidHubV1 INTRO: a readiness-gated black-and-white loading splash.
-- Cosmetic only: no combat/input behavior changed. Never hides on a timer
-- until every synchronous GUI initialization step has completed.
local function showVoidSlayerIntro()
    -- VOID HUB // premium monochrome boot sequence.
    -- Progress is held below 100% until the whole GUI has been built.
    local previous = PlayerGui:FindFirstChild("VoidHubV1_Intro")
    if previous then previous:Destroy() end
    local bootStarted = os.clock()

    local introGui = Instance.new("ScreenGui")
    introGui.Name = "VoidHubV1_Intro"
    introGui.IgnoreGuiInset = true
    introGui.ResetOnSpawn = false
    introGui.DisplayOrder = 100001
    introGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    introGui.Parent = PlayerGui

    local function round(obj, pixels)
        local r = Instance.new("UICorner")
        r.CornerRadius = UDim.new(0, pixels)
        r.Parent = obj
    end
    local function frame(name, parent, position, size, color, alpha, radius)
        local obj = Instance.new("Frame")
        obj.Name = name
        obj.Position = position
        obj.Size = size
        obj.BackgroundColor3 = color
        obj.BackgroundTransparency = alpha or 0
        obj.BorderSizePixel = 0
        obj.Parent = parent
        if radius then round(obj, radius) end
        return obj
    end
    local function label(name, parent, position, size, text, font, textSize, color, alignment)
        local obj = Instance.new("TextLabel")
        obj.Name = name
        obj.Position = position
        obj.Size = size
        obj.BackgroundTransparency = 1
        obj.Font = font
        obj.Text = text
        obj.TextSize = textSize
        obj.TextColor3 = color
        obj.TextTransparency = 1
        obj.TextXAlignment = alignment or Enum.TextXAlignment.Center
        obj.TextYAlignment = Enum.TextYAlignment.Center
        obj.TextTruncate = Enum.TextTruncate.AtEnd
        obj.Parent = parent
        return obj
    end
    local function tween(obj, seconds, properties, style, direction)
        local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad,
            direction or Enum.EasingDirection.Out)
        local motion = TweenService:Create(obj, info, properties)
        motion:Play()
        return motion
    end

    local veil = frame("BootBackdrop", introGui, UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1), Color3.fromRGB(4, 5, 7), 1)
    local night = Instance.new("UIGradient")
    night.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(3, 4, 7)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(13, 15, 19)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 6, 9))})
    night.Rotation = 35
    night.Parent = veil

    -- A low-contrast floating halo creates depth without neon or image assets.
    local halo = frame("FloatingHalo", veil, UDim2.fromScale(0.5, 0.5),
        UDim2.new(0.91, 18, 0, 338), Color3.fromRGB(255, 255, 255), 1, 22)
    halo.AnchorPoint = Vector2.new(0.5, 0.5)
    local haloLimit = Instance.new("UISizeConstraint")
    haloLimit.MinSize = Vector2.new(254, 338)
    haloLimit.MaxSize = Vector2.new(570, 338)
    haloLimit.Parent = halo
    local haloOutline = Instance.new("UIStroke")
    haloOutline.Color = Color3.fromRGB(214, 222, 235)
    haloOutline.Transparency = 1
    haloOutline.Thickness = 3
    haloOutline.Parent = halo

    local card = frame("BootCard", veil, UDim2.fromScale(0.5, 0.5),
        UDim2.new(0.90, 0, 0, 316), Color3.fromRGB(17, 19, 24), 1, 18)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.ClipsDescendants = true
    local widthLimit = Instance.new("UISizeConstraint")
    widthLimit.MinSize = Vector2.new(248, 316)
    widthLimit.MaxSize = Vector2.new(552, 316)
    widthLimit.Parent = card
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Name = "SilverBorder"
    cardStroke.Color = Color3.fromRGB(227, 232, 240)
    cardStroke.Thickness = 1.5
    cardStroke.Transparency = 1
    cardStroke.Parent = card
    local finish = Instance.new("UIGradient")
    finish.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(34, 37, 44)),
        ColorSequenceKeypoint.new(0.48, Color3.fromRGB(17, 19, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 13))})
    finish.Rotation = 93
    finish.Parent = card
    local cardScale = Instance.new("UIScale")
    cardScale.Scale = 0.89
    cardScale.Parent = card

    local headerLeft = label("Brand", card, UDim2.new(0, 26, 0, 16),
        UDim2.new(0.56, -27, 0, 20), "VS / VOIDSLAYERXX",
        Enum.Font.GothamBold, 11, Color3.fromRGB(244, 246, 250),
        Enum.TextXAlignment.Left)
    local headerRight = label("EditionTag", card, UDim2.new(0.56, 0, 0, 16),
        UDim2.new(0.44, -26, 0, 20), "PRIVATE  /  V1",
        Enum.Font.GothamMedium, 10, Color3.fromRGB(164, 169, 178),
        Enum.TextXAlignment.Right)
    local topRule = frame("HeaderHairline", card, UDim2.fromOffset(26, 47),
        UDim2.new(1, -52, 0, 1), Color3.fromRGB(211, 219, 231), 0.80)
    local ruleGradient = Instance.new("UIGradient")
    ruleGradient.Color = ColorSequence.new(
        Color3.fromRGB(246, 248, 251), Color3.fromRGB(78, 85, 97))
    ruleGradient.Parent = topRule

    local ring = frame("VoidGlyph", card, UDim2.new(0.5, -30, 0, 67),
        UDim2.fromOffset(60, 60), Color3.fromRGB(245, 246, 249), 0.95, 17)
    local ringStroke = Instance.new("UIStroke")
    ringStroke.Color = Color3.fromRGB(245, 247, 251)
    ringStroke.Thickness = 1.6
    ringStroke.Transparency = 1
    ringStroke.Parent = ring
    local glyph = label("Glyph", ring, UDim2.fromScale(0, 0),
        UDim2.fromScale(1, 1), "V", Enum.Font.GothamBlack, 33,
        Color3.fromRGB(255, 255, 255))
    local glyphBar = frame("GlyphBar", ring, UDim2.fromOffset(14, 48),
        UDim2.fromOffset(32, 2), Color3.fromRGB(244, 246, 251), 0.65, 1)

    local title = label("Title", card, UDim2.new(0, 24, 0, 138),
        UDim2.new(1, -48, 0, 49), "V O I D   H U B",
        Enum.Font.GothamBlack, 36, Color3.fromRGB(255, 255, 255))
    title.TextScaled = true
    local titleSize = Instance.new("UITextSizeConstraint")
    titleSize.MinTextSize = 20
    titleSize.MaxTextSize = 36
    titleSize.Parent = title

    local subtitle = label("Descriptor", card, UDim2.new(0, 24, 0, 186),
        UDim2.new(1, -48, 0, 19), "THE MONOCHROME COMMAND CENTER",
        Enum.Font.GothamMedium, 11, Color3.fromRGB(177, 183, 194))
    local miniRule = frame("CenterAccent", card, UDim2.new(0.5, -20, 0, 210),
        UDim2.fromOffset(40, 1), Color3.fromRGB(255, 255, 255), 0.25)

    local stage = label("BootStage", card, UDim2.fromOffset(27, 226),
        UDim2.new(0.76, -26, 0, 18), "PREPARING INTERFACE",
        Enum.Font.GothamBold, 10, Color3.fromRGB(211, 216, 226),
        Enum.TextXAlignment.Left)
    local percentage = label("ProgressPercent", card, UDim2.new(0.76, 0, 0, 226),
        UDim2.new(0.24, -27, 0, 18), "00%",
        Enum.Font.GothamBold, 12, Color3.fromRGB(255, 255, 255),
        Enum.TextXAlignment.Right)
    local track = frame("ProgressTrack", card, UDim2.fromOffset(27, 251),
        UDim2.new(1, -54, 0, 5), Color3.fromRGB(66, 70, 79), 0.18, 3)
    local progress = frame("ProgressFill", track, UDim2.fromScale(0, 0),
        UDim2.fromScale(0, 1), Color3.fromRGB(246, 248, 252), 0, 3)
    local fillFinish = Instance.new("UIGradient")
    fillFinish.Color = ColorSequence.new(
        Color3.fromRGB(185, 194, 209), Color3.fromRGB(255, 255, 255))
    fillFinish.Parent = progress

    local footerRule = frame("FooterRule", card, UDim2.fromOffset(27, 275),
        UDim2.new(1, -54, 0, 1), Color3.fromRGB(196, 201, 211), 0.86)
    local footer = label("Footer", card, UDim2.fromOffset(27, 284),
        UDim2.new(1, -54, 0, 18), "DEFENSE  /  ATTACK  /  MOVEMENT  /  VISUALS",
        Enum.Font.Gotham, 10, Color3.fromRGB(136, 143, 154))

    -- A soft scanning highlight: no camera movement, sound, or user input.
    local scan = frame("ScanHighlight", card, UDim2.fromOffset(0, 60),
        UDim2.new(1, 0, 0, 1), Color3.fromRGB(240, 245, 255), 0.95)
    scan.ZIndex = 2
    scan.Active = false

    Gui.Destroying:Connect(function()
        if introGui.Parent then introGui:Destroy() end
    end)

    task.spawn(function()
        while introGui.Parent and Gui.Parent and not guiFullyLoaded do
            scan.Position = UDim2.fromOffset(0, 59)
            local sweep = tween(scan, 1.8, {Position = UDim2.new(0, 0, 1, -14)},
                Enum.EasingStyle.Linear)
            sweep.Completed:Wait()
            task.wait(0.14)
        end
    end)

    task.spawn(function()
        local ok, message = pcall(function()
            tween(veil, 0.45, {BackgroundTransparency = 0.09})
            tween(haloOutline, 0.75, {Transparency = 0.88})
            tween(card, 0.48, {BackgroundTransparency = 0.035})
            tween(cardStroke, 0.60, {Transparency = 0.32})
            tween(cardScale, 0.70, {Scale = 1}, Enum.EasingStyle.Back)
            tween(ringStroke, 0.65, {Transparency = 0.30})
            for i, obj in ipairs({headerLeft, headerRight, glyph,
                title, subtitle, stage, percentage, footer}) do
                tween(obj, 0.38 + i * 0.055, {TextTransparency = 0})
            end

            -- This is a real readiness gate, not a fake fixed-duration loader.
            while introGui.Parent and Gui.Parent do
                local elapsed = os.clock() - bootStarted
                local ratio = math.min(0.92, 0.06 + elapsed * 0.44)
                progress.Size = UDim2.fromScale(ratio, 1)
                percentage.Text = ("%02d%%"):format(math.floor(ratio * 100 + 0.5))
                if not guiFullyLoaded then
                    if elapsed < 0.7 then
                        stage.Text = "LOADING CORE COMPONENTS"
                    elseif elapsed < 1.6 then
                        stage.Text = "ORGANIZING COMMAND MODULES"
                    else
                        stage.Text = "WAITING FOR INTERFACE READY"
                    end
                else
                    stage.Text = "FINALIZING VOID HUB"
                end
                if guiFullyLoaded and elapsed >= 1.75 then break end
                task.wait(0.045)
            end
            if not introGui.Parent or not Gui.Parent then return end
            stage.Text = "ALL SYSTEMS READY"
            footer.Text = "VOIDSLAYERXX  /  INTERFACE INITIALIZED"
            tween(ringStroke, 0.28, {Transparency = 0.05})
            local finishBar = tween(progress, 0.38, {Size = UDim2.fromScale(1, 1)},
                Enum.EasingStyle.Quart)
            finishBar.Completed:Wait()
            percentage.Text = "100%"
            task.wait(0.26)
            if not introGui.Parent then return end

            tween(cardScale, 0.38, {Scale = 1.035}, Enum.EasingStyle.Quad,
                Enum.EasingDirection.In)
            tween(card, 0.37, {BackgroundTransparency = 1})
            tween(cardStroke, 0.37, {Transparency = 1})
            tween(haloOutline, 0.35, {Transparency = 1})
            for _, obj in ipairs(introGui:GetDescendants()) do
                if obj:IsA("TextLabel") then
                    tween(obj, 0.36, {TextTransparency = 1})
                elseif obj:IsA("Frame") and obj ~= veil then
                    tween(obj, 0.36, {BackgroundTransparency = 1})
                elseif obj:IsA("UIStroke") then
                    tween(obj, 0.36, {Transparency = 1})
                end
            end
            local exit = tween(veil, 0.44, {BackgroundTransparency = 1},
                Enum.EasingStyle.Quad, Enum.EasingDirection.In)
            exit.Completed:Wait()
        end)
        if introGui.Parent then introGui:Destroy() end
        if not ok then warn("[VOID HUB] Intro fallback cleanup: " .. tostring(message)) end
    end)
end
showVoidSlayerIntro()


local GlobalConnections = {}
local function bindGlobal(signal, callback)
	local c = signal:Connect(callback)
	GlobalConnections[#GlobalConnections + 1] = c
	return c
end

-- Real manual G must have priority over all automatic carry and
-- teleport tools. Detect unexpected large post-G server jumps without
-- assuming that the destination is a specific classroom coordinate.
-- Keep only the shared checker as a top-level upvalue. All manual G
-- state lives inside its own lexical scope to avoid Luau's 200-register limit.
local isManualGrabWindow
do
local manualGrabHeld = false
local manualGrabGraceUntil = -math.huge
local MANUAL_GRAB_FINISH_GRACE = 18.0
local MANUAL_GRAB_RESCUE_WINDOW = 24.0
local manualGrabRescueUntil = -math.huge
local manualGrabSafePivot, manualGrabPreviousPivot, manualGrabCharacter = nil, nil, nil
local manualGrabCorrections, manualGrabLastCorrection = 0, -math.huge
local manualGrabLastStatus = "No post-G jump observed"
isManualGrabWindow = function()
    return manualGrabHeld or UIS:IsKeyDown(Enum.KeyCode.G)
        or os.clock() < manualGrabGraceUntil
end
local function beginManualGrab()
    local c = Player.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if c and h and h.Health > 0 and r then
        manualGrabSafePivot = c:GetPivot()
        manualGrabPreviousPivot = manualGrabSafePivot
        manualGrabCharacter = c
    else
        manualGrabSafePivot, manualGrabPreviousPivot = nil, nil
        manualGrabCharacter = nil
    end
    manualGrabCorrections, manualGrabLastCorrection = 0, -math.huge
    manualGrabRescueUntil = os.clock() + MANUAL_GRAB_RESCUE_WINDOW
    manualGrabLastStatus = "Manual G recognized"
end
bindGlobal(UIS.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.G and not UIS:GetFocusedTextBox() then
        if not manualGrabHeld then beginManualGrab() end
        manualGrabHeld = true
        manualGrabGraceUntil = os.clock() + MANUAL_GRAB_FINISH_GRACE
    end
end)
bindGlobal(UIS.InputEnded, function(input)
    if input.KeyCode == Enum.KeyCode.G then
        manualGrabHeld = false
        manualGrabGraceUntil = os.clock() + MANUAL_GRAB_FINISH_GRACE
        manualGrabRescueUntil = math.max(manualGrabRescueUntil,
            os.clock() + MANUAL_GRAB_RESCUE_WINDOW)
    end
end)
bindGlobal(Player.CharacterAdded, function()
    manualGrabHeld = false
    manualGrabGraceUntil, manualGrabRescueUntil = -math.huge, -math.huge
    manualGrabSafePivot, manualGrabPreviousPivot, manualGrabCharacter = nil, nil, nil
    manualGrabCorrections = 0
    manualGrabLastStatus = "Respawned; G guard reset"
end)
bindGlobal(RunService.Heartbeat, function()
    local now = os.clock()
    if not Gui.Parent or now >= manualGrabRescueUntil then return end
    local c = Player.Character
    if c ~= manualGrabCharacter or not manualGrabSafePivot then return end
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health <= 0 or not r then return end
    local previous = manualGrabPreviousPivot
    if not previous then manualGrabPreviousPivot = c:GetPivot() return end
    local distance = (r.Position - previous.Position).Magnitude
    local intentional = DeathTPIsEscaping or SharedTeleportOwner ~= nil
        or now < AntiTPIntentionalTeleportUntil
    if distance >= 40 and not intentional then
        manualGrabLastStatus = ("Sudden G jump: %.1f studs"):format(distance)
        if manualGrabCorrections < 3
            and now - manualGrabLastCorrection >= 0.20 then
            manualGrabCorrections += 1
            manualGrabLastCorrection = now
            local ok = pcall(function() c:PivotTo(previous) end)
            warn("[VOID HUB G] " .. manualGrabLastStatus
                .. (ok and " - local return attempted" or " - return failed")
                .. "; server teleports cannot be guaranteed to reverse.")
            if ok then manualGrabPreviousPivot = previous return end
        end
    end
    if distance < 40 and not intentional then
        manualGrabPreviousPivot = c:GetPivot()
    end
end)
end -- close manual G local-state scope, but keep G checker available

local espHighlights = {}
local tracerLines = {}
local headLabels = {}

local function cleanupVisuals()
	for plr, hl in pairs(espHighlights) do
		if hl then pcall(function() hl:Destroy() end) end
		espHighlights[plr] = nil
	end
	for plr, line in pairs(tracerLines) do
		if line then pcall(function() line:Destroy() end) end
		tracerLines[plr] = nil
	end
	for plr, gui in pairs(headLabels) do
		if gui then pcall(function() gui:Destroy() end) end
		headLabels[plr] = nil
	end
end

Gui.Destroying:Connect(function()
	cleanupVisuals()
	for _, c in ipairs(GlobalConnections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(GlobalConnections)
end)

local function corner(obj, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = obj
	return c
end

local function stroke(obj, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(200, 200, 210)
	s.Thickness = thickness or 1
	s.Transparency = 0.1
	s.Parent = obj
	return s
end

local Holder = Instance.new("Frame")
Holder.Name = "Holder"
Holder.ZIndex = 10 -- Keep the hub panel above the in-world tracer overlay.
Holder.AnchorPoint = Vector2.new(0.5, 0.5)
Holder.Position = UDim2.fromScale(0.5, 0.5)
Holder.Size = UDim2.fromOffset(940, 610)
Holder.BackgroundTransparency = 1
Holder.Visible = true
Holder.Parent = Gui

local PanelScale = Instance.new("UIScale")
PanelScale.Name = "PanelScale"
PanelScale.Scale = 0.88
PanelScale.Parent = Holder

local panelSizeStep = math.clamp(tonumber(savedUI.misc.windowSize) or 7, 3, 14) -- restored window size

local function updatePanelScale()
    savedUI.misc.windowSize = panelSizeStep
    queueUISave()
	local camera = workspace.CurrentCamera
	if not camera then
		PanelScale.Scale = 0.88 * (panelSizeStep / 10)
		return
	end
	local v = camera.ViewportSize
	local sx = math.max((v.X - 24) / 940, 0.30)
	local sy = math.max((v.Y - 24) / 610, 0.30)
	local autoScale = math.clamp(math.min(sx, sy, 0.88), 0.30, 0.88)
	PanelScale.Scale = math.max(0.18, math.min(autoScale * (panelSizeStep / 10), sx, sy))
end
updatePanelScale()

if workspace.CurrentCamera then
	bindGlobal(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), updatePanelScale)
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(940, 610)
Main.BackgroundColor3 = Color3.fromRGB(246, 248, 252)
Main.BorderSizePixel = 0
Main.Active = true
corner(Main, 12)
stroke(Main, Color3.fromRGB(180, 185, 200), 1)
Main.Parent = Holder

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.BackgroundTransparency = 1
Title.Position = UDim2.fromOffset(22, 14)
Title.Size = UDim2.fromOffset(180, 28)
Title.Font = Enum.Font.GothamBlack
Title.Text = "VoidHubV1"
Title.TextColor3 = Color3.fromRGB(30, 32, 40)
Title.TextSize = 21
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Main

local function killScript()
    saveUISettings()
	cleanupVisuals()
	for _, c in ipairs(GlobalConnections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(GlobalConnections)
	if Gui and Gui.Parent then
		Gui:Destroy()
	end
	print("VOID HUB fully unloaded")
end

local KillBtn = Instance.new("TextButton")
KillBtn.Name = "KillBtn"
KillBtn.Size = UDim2.fromOffset(67, 30)
KillBtn.Position = UDim2.fromOffset(853, 12)
KillBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
KillBtn.Text = "UNLOAD"
KillBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
KillBtn.TextSize = 10
KillBtn.Font = Enum.Font.GothamBold
KillBtn.AutoButtonColor = false
KillBtn.ZIndex = 20
corner(KillBtn, 8)
KillBtn.Parent = Main
KillBtn.Activated:Connect(killScript)

local function makeSizeButton(name, caption, x)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(34, 30)
	button.Position = UDim2.fromOffset(x, 12)
	button.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	button.Text = caption
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextSize = 18
	button.Font = Enum.Font.GothamBold
	button.AutoButtonColor = true
	button.ZIndex = 20
	corner(button, 8)
	button.Parent = Main
	return button
end

local SizeDownBtn = makeSizeButton("SizeDown", "â", 662)
local SizeUpBtn = makeSizeButton("SizeUp", "+", 776)
local SizeIndicator = Instance.new("TextLabel")
SizeIndicator.Name = "SizePercent"
SizeIndicator.Size = UDim2.fromOffset(70, 30)
SizeIndicator.Position = UDim2.fromOffset(702, 12)
SizeIndicator.BackgroundTransparency = 1
SizeIndicator.Font = Enum.Font.GothamBold
SizeIndicator.TextSize = 13
SizeIndicator.TextColor3 = Color3.fromRGB(25, 25, 30)
SizeIndicator.Text = "70%"
SizeIndicator.ZIndex = 20
SizeIndicator.Parent = Main

local function setPanelSizeStep(nextStep)
	panelSizeStep = math.clamp(nextStep, 6, 14)
	SizeIndicator.Text = tostring(panelSizeStep * 10) .. "%"
	SizeDownBtn.BackgroundColor3 = panelSizeStep == 6 and Color3.fromRGB(105, 105, 110) or Color3.fromRGB(20, 20, 25)
	SizeUpBtn.BackgroundColor3 = panelSizeStep == 14 and Color3.fromRGB(105, 105, 110) or Color3.fromRGB(20, 20, 25)
	updatePanelScale()

	local camera = workspace.CurrentCamera
	if camera then
		local viewport = camera.ViewportSize
		if viewport.X > 0 and viewport.Y > 0 then
			local halfW = 940 * PanelScale.Scale * 0.5
			local halfH = 610 * PanelScale.Scale * 0.5
			local pos = Holder.Position
			local x = viewport.X * pos.X.Scale + pos.X.Offset
			local y = viewport.Y * pos.Y.Scale + pos.Y.Offset
			x = math.clamp(x, halfW + 10, math.max(halfW + 10, viewport.X - halfW - 10))
			y = math.clamp(y, halfH + 10, math.max(halfH + 10, viewport.Y - halfH - 10))
			Holder.Position = UDim2.fromScale(x / viewport.X, y / viewport.Y)
		end
	end
end
SizeDownBtn.Activated:Connect(function()
	setPanelSizeStep(panelSizeStep - 1)
end)
SizeUpBtn.Activated:Connect(function()
	setPanelSizeStep(panelSizeStep + 1)
end)

local segmentNames = {"Defense", "Attack", "Movement", "Visual", "Abuse"}
local segmentButtons = {}
local activeSegment = nil
local pages = {}

local SEGMENT_H = 36
local SEGMENT_GAP = 10
local SEGMENT_PAD = 22
local SEGMENT_Y = 52
local SEGMENT_W = math.floor((940 - SEGMENT_PAD * 2 - SEGMENT_GAP * (#segmentNames - 1)) / #segmentNames)

local NORMAL_BG = Color3.fromRGB(34, 34, 38) -- monochrome idle tabs
local ACTIVE_BG = Color3.fromRGB(255, 255, 255) -- white selected tab
local NORMAL_TEXT = Color3.fromRGB(239, 239, 243)
local ACTIVE_TEXT = Color3.fromRGB(18, 18, 21)

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Position = UDim2.fromOffset(22, 100)
Content.Size = UDim2.fromOffset(896, 490)
Content.BackgroundTransparency = 1
Content.Parent = Main

local function makePage(name)
	local p = Instance.new("ScrollingFrame")
	p.Name = name
	p.Size = UDim2.fromScale(1, 1)
	p.BackgroundTransparency = 1
	p.BorderSizePixel = 0
	p.ScrollBarThickness = 4
	p.CanvasSize = UDim2.fromOffset(0, 520)
	p.Visible = false
	p.Parent = Content
	pages[name] = p
	return p
end

for _, name in ipairs(segmentNames) do
	makePage(name)
end

local DefensePage = pages["Defense"]
DefensePage.CanvasSize = UDim2.fromOffset(0, 825)

local DefenseHeading = Instance.new("TextLabel")
DefenseHeading.Name = "DefenseHeading"
DefenseHeading.BackgroundTransparency = 1
DefenseHeading.Position = UDim2.fromOffset(0, 0)
DefenseHeading.Size = UDim2.fromOffset(880, 28)
DefenseHeading.Text = "DEFENSE  |  Anti Grab  â¢  Anti TP  â¢  Anti Ragdoll  â¢  Anti Void  â¢  Death TP  â¢  Auto Block"
DefenseHeading.TextColor3 = Color3.fromRGB(40, 42, 55)
DefenseHeading.TextSize = 13
DefenseHeading.Font = Enum.Font.GothamBold
DefenseHeading.TextXAlignment = Enum.TextXAlignment.Left
DefenseHeading.Parent = DefensePage

local function setSegment(name)
    if not pages[name] then return end
    activeSegment = name
    for n, b in pairs(segmentButtons) do
        local selected = n == name
        b.BackgroundColor3 = selected and ACTIVE_BG or NORMAL_BG
        b.TextColor3 = selected and ACTIVE_TEXT or NORMAL_TEXT
        local outline = b:FindFirstChild("WhiteGlowTabStroke")
        if outline then outline.Transparency = selected and 0.06 or 0.70 end
    end
    for n, p in pairs(pages) do
        p.Visible = (n == name)
        if n == name then p.CanvasPosition = Vector2.new(0, 0) end
    end
    -- Keep section shortcuts visible while content scrolls.
    for _, nav in ipairs(Content:GetChildren()) do
        if nav:IsA("Frame") and nav.Name:sub(1, 18) == "V1QuickNavigation_" then
            nav.Visible = nav.Name == "V1QuickNavigation_" .. name
        end
    end
end

for i, name in ipairs(segmentNames) do
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(SEGMENT_W, SEGMENT_H)
	b.Position = UDim2.fromOffset(SEGMENT_PAD + (i - 1) * (SEGMENT_W + SEGMENT_GAP), SEGMENT_Y)
	b.BackgroundColor3 = NORMAL_BG
	b.Text = (name == "Abuse") and "Monitor" or name
	b.TextColor3 = NORMAL_TEXT
	b.TextSize = 12
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = false
	b.ZIndex = 10
	corner(b, 8)
	b.Parent = Main
	segmentButtons[name] = b
	b.Activated:Connect(function()
		setSegment(name)
        savedUI.misc.lastTab = name
        queueUISave()
	end)
end

local State = {
	ESP = false,
	Tracers = false,
	ESPBind = nil,
	TracersBind = nil,
	ShowWhitelist = true,
	ShowBlacklist = true,
	Whitelist = {},
	Blacklist = {},
}
savedStateGetter = function() return State end
if type(savedUI.misc.showWhitelist) == "boolean" then State.ShowWhitelist = savedUI.misc.showWhitelist end
if type(savedUI.misc.showBlacklist) == "boolean" then State.ShowBlacklist = savedUI.misc.showBlacklist end
local function restoreKeybind(k)
    local name = savedUI.misc[k]
    if type(name) == "string" and name ~= "" then return Enum.KeyCode[name] end
end
State.ESPBind = restoreKeybind("espBind")
State.TracersBind = restoreKeybind("tracersBind")
local waitingForBind = nil

local function animateToggle(btn, on)
	local targetBg = on and Color3.fromRGB(20, 20, 25) or Color3.fromRGB(230, 232, 240)
	local targetText = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(40, 42, 55)
	TweenService:Create(btn, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundColor3 = targetBg
	}):Play()
	btn.TextColor3 = targetText
end

local function keyName(code)
	if not code then return "None" end
	return tostring(code):gsub("Enum.KeyCode.", "")
end

local function blacklistHasEntries()
	for _ in pairs(State.Blacklist) do return true end
	return false
end

local function resolveUniqueListedName(fragment)
    if type(fragment) ~= "string" or fragment == "" then return nil end
    local key = fragment:lower()
    local bestTier, bestPlayer, ties = math.huge, nil, 0

    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= Player then
            local username = candidate.Name:lower()
            local display = candidate.DisplayName:lower()
            local tier
            if username == key then
                tier = 1
            elseif display == key then
                tier = 2
            elseif username:sub(1, #key) == key then
                tier = 3
            elseif display:sub(1, #key) == key then
                tier = 4
            elseif username:find(key, 1, true) then
                tier = 5
            elseif display:find(key, 1, true) then
                tier = 6
            end

            if tier then
                if tier < bestTier then
                    bestTier, bestPlayer, ties = tier, candidate, 1
                elseif tier == bestTier then
                    ties += 1
                end
            end
        end
    end
    return ties == 1 and bestPlayer or nil, ties > 1
end

local function inPlayerList(list, plr)
    if not plr or not plr:IsA("Player") then return false end
    local username = plr.Name:lower()
    local displayName = plr.DisplayName:lower()
    if list[username] == true then return true end

    if list == State.Whitelist then
        for fragment, enabled in pairs(list) do
            if enabled and type(fragment) == "string" and fragment ~= "" then
                local key = fragment:lower()
                if username:find(key, 1, true) or displayName:find(key, 1, true) then
                    return true
                end
            end
        end
    else
        for fragment in pairs(list) do
            if resolveUniqueListedName(fragment) == plr then
                return true
            end
        end
    end
    return false
end
local function isBad(plr)
	return inPlayerList(State.Blacklist, plr)
end
local function isSafe(plr)
	return not isBad(plr) and inPlayerList(State.Whitelist, plr)
end
local function shouldTarget(plr)
	if plr == Player or isSafe(plr) then return false end
	if blacklistHasEntries() then return isBad(plr) end
	return true
end

local function shouldFreezeTarget(plr)
    if not plr or not plr:IsA("Player") or plr == Player or not plr.Parent then
        return false
    end
    if inPlayerList(State.Whitelist, plr) then return false end
    if State.Blacklist["all"] then return true end
    return inPlayerList(State.Blacklist, plr)
end

local function resolveName(query)
	query = string.lower(string.gsub(query, "^%s*(.-)%s*$", "%1"))
	if query == "" then return nil end

	local best = nil
	local bestScore = math.huge

	local function consider(plr, label)
		local lower = string.lower(label)
		if string.sub(lower, 1, #query) == query then
			local score = #label
			if score < bestScore then
				bestScore = score
				best = plr.Name
			end
			return true
		end
		return false
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Player then
			consider(plr, plr.Name)
			if plr.DisplayName and plr.DisplayName ~= plr.Name then
				consider(plr, plr.DisplayName)
			end
		end
	end

	if best then return best end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Player then
			local candidates = { plr.Name }
			if plr.DisplayName and plr.DisplayName ~= plr.Name then
				candidates[#candidates + 1] = plr.DisplayName
			end
			for _, label in ipairs(candidates) do
				local lower = string.lower(label)
				local idx = string.find(lower, query, 1, true)
				if idx then
					local score = #label + (idx - 1) * 10
					if score < bestScore then
						bestScore = score
						best = plr.Name
					end
				end
			end
		end
	end

	return best
end

local function parseNames(text)
	local results = {}
	for token in string.gmatch(text, "[^,%s]+") do
		local key = token:lower():gsub("^@", "")
		if key ~= "" then results[key] = true end
	end
	return results
end

local function makeFeatureCard(parent, title, y)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(430, 90)
	card.Position = UDim2.fromOffset(0, y)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	corner(card, 10)
	stroke(card, Color3.fromRGB(210, 214, 225), 1)
	card.Parent = parent
	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Position = UDim2.fromOffset(16, 12)
	titleLbl.Size = UDim2.fromOffset(200, 22)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Text = title
	titleLbl.TextColor3 = Color3.fromRGB(30, 32, 40)
	titleLbl.TextSize = 15
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = card
	return card
end

do
    local RS = game:GetService("ReplicatedStorage")
    local page = pages["Attack"]
    page.CanvasSize = UDim2.fromOffset(0, 1230)
    local card = makeFeatureCard(page, "Bring / Carry", 0)
    card.Name = "AttackCarryControl"
    card.Size = UDim2.fromOffset(880, 217)
    card:FindFirstChildOfClass("TextLabel").Size = UDim2.fromOffset(720, 24)

    local function makeLabel(name, value, x, y, w, h, fontSize)
        local obj = Instance.new("TextLabel")
        obj.Name = name
        obj.Size = UDim2.fromOffset(w, h)
        obj.Position = UDim2.fromOffset(x, y)
        obj.BackgroundTransparency = 1
        obj.Font = Enum.Font.Gotham
        obj.TextSize = fontSize or 12
        obj.TextColor3 = Color3.fromRGB(51, 56, 72)
        obj.TextXAlignment = Enum.TextXAlignment.Left
        obj.TextYAlignment = Enum.TextYAlignment.Top
        obj.TextWrapped = true
        obj.Text = value
        obj.Parent = card
        return obj
    end
    local function makeButton(name, value, x, y, w, h, bg, fg)
        local btn = Instance.new("TextButton")
        btn.Name = name
        btn.Position = UDim2.fromOffset(x, y)
        btn.Size = UDim2.fromOffset(w, h)
        btn.BackgroundColor3 = bg or Color3.fromRGB(225, 231, 241)
        btn.TextColor3 = fg or Color3.fromRGB(25, 30, 43)
        btn.Text = value
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.AutoButtonColor = true
        btn.Parent = card
        corner(btn, 8)
        return btn
    end

    makeLabel("Hint", "BRING: player / ALL | INSTA: one | GYMBAN: ON/OFF; repeats at a controlled interval.", 16, 41, 845, 20, 12)
    local input = Instance.new("TextBox")
    input.Name = "TargetUsername"
    input.Position = UDim2.fromOffset(16, 71)
    input.Size = UDim2.fromOffset(399, 40)
    input.Text = ""
    input.PlaceholderText = "Name, username, part of name, or ALL"
    input.ClearTextOnFocus = false
    input.BackgroundColor3 = Color3.fromRGB(239, 243, 250)
    input.TextColor3 = Color3.fromRGB(25, 30, 43)
    input.TextSize = 14
    input.Font = Enum.Font.Gotham
    input.Parent = card
    corner(input, 8)

    local bring = makeButton("Bring", "BRING", 430, 71, 140, 40)
    local instantSky = makeButton("InstantSky", "INSTA", 583, 71, 152, 40,
        Color3.fromRGB(218, 230, 248), Color3.fromRGB(21, 48, 92))
    local clear = makeButton("ClearTarget", "CLEAR", 749, 71, 113, 40)
    local gymbanButton = makeButton("Gymban", "GYMBAN: OFF", 693, 10, 169, 29,
        Color3.fromRGB(225, 231, 241), Color3.fromRGB(25, 30, 43))
    local status = makeLabel("AttackStatus", "Ready. Choose a player or ALL and press BRING.",
        16, 123, 840, 27, 12)
    local rules = makeLabel("AttackRules", "", 16, 158, 845, 46, 12)
    local function count(dict)
        local n = 0
        for _ in pairs(dict) do n += 1 end
        return n
    end
    local function isBringProtected(other)
        return other ~= nil and inPlayerList(State.Whitelist, other)
    end

    local function shouldBringAllTarget(other)
        if not other or other == Player or not other.Parent or isBringProtected(other) then
            return false
        end
        if not blacklistHasEntries() or State.Blacklist["all"] then
            return true
        end
        return inPlayerList(State.Blacklist, other)
    end

    local function updateRules()
        local allMode = (not blacklistHasEntries() or State.Blacklist["all"])
            and "everyone except Whitelist" or "only Blacklist players (except Whitelist)"
        rules.Text = ("Whitelist protects GROUP name matches from Bring + Freeze. BRING ALL: %s.\n" ..
            "Whitelist patterns: %d   |   Blacklist: %d. Press BRING again to cancel ALL.")
            :format(allMode, count(State.Whitelist), count(State.Blacklist))
    end

    local activeRevision = 0
    local sendingAll = false
    local gymbanRunning = false
    local gymbanRevision = 0
    local gymbanTarget = nil
    local gymbanTargetName = nil
    local gymbanAllMode = false
    local gymbanConnections = {}
    local gymbanAddedConnection = nil
    local gymbanRemovingConnection = nil
    local gymbanQueue = {}
    local gymbanScheduled = {}
    local gymbanWorkerRevision = nil
    local GYMBAN_SPAWN_READY_DELAY = 0.15 -- faster response after spawn
    local GYMBAN_BETWEEN_TARGETS = 0.45
    local GYMBAN_LOOP_INTERVAL = 1.05 -- every living target repeats; keep server requests bounded
    local GYMBAN_MIN_GLOBAL_INTERVAL = 0.55
    local lastGymbanRequestAt = -math.huge

    local INSTANT_SKY_CARRY_ARG2 = 1
    local INSTANT_SKY_CARRY_ARG3 = 700 -- GymBan, matching INSTA
    local INSTA_BUTTON_CARRY_ARG3 = 700 -- INSTA button only
    local EVENT_CFRAME = CFrame.new(53.5, 8.298911, 118.149994)
    local BRING_CARRY_WAIT = 0.12
    local BRING_TELEPORT_WAIT = 0.08
    local BRING_RETURN_DURATION = 0.8
    local bringBusy = false
    local returnConn = nil

    local function startReturnHold(savedCFrame, duration)
        if returnConn then
            returnConn:Disconnect()
            returnConn = nil
        end
        if not savedCFrame then return end
        local startTime = tick()
        returnConn = RunService.Heartbeat:Connect(function()
            if tick() - startTime > (duration or 0.8) then
                if returnConn then
                    returnConn:Disconnect()
                    returnConn = nil
                end
                return
            end
            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if hrp and (hrp.Position - savedCFrame.Position).Magnitude > 7 then
                -- Correct actual teleport jumps only; do not freeze normal movement.
                pcall(function()
                    hrp.CFrame = savedCFrame
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end)
            end
        end)
    end

    local function computeArgsForDesired(desiredPos, eventPos)
        local a2 = eventPos.X - desiredPos.X
        local a3 = eventPos.Y - desiredPos.Y
        local a4 = eventPos.Z - desiredPos.Z
        local function roundn(n) return math.floor(n + 0.5) end
        return roundn(a2), roundn(a3), roundn(a4)
    end

    local function doBringOne(target, a2, a3, a4, mySavedCFrame)
        if isManualGrabWindow() then return end
        pcall(function()
            if RS:FindFirstChild("CarryRequest") then
                RS.CarryRequest:FireServer(table.unpack({
                    [1] = target,
                    [2] = a2,
                    [3] = a3,
                    [4] = a4,
                    [5] = 0, [6] = 0, [7] = 0,
                }))
            end
        end)
        task.wait(BRING_CARRY_WAIT)
        if isManualGrabWindow() then return end
        if not isManualGrabWindow() then
            AntiTPIntentionalTeleportUntil = os.clock() + 1.6
            pcall(function()
                local evRoot = RS:FindFirstChild("EventInviteSystem")
                if evRoot and evRoot:FindFirstChild("EventTeleportEvent") then
                    evRoot.EventTeleportEvent:FireServer()
                elseif RS:FindFirstChild("EventTeleportEvent") then
                    RS.EventTeleportEvent:FireServer()
                end
            end)
        end
        pcall(function()
            local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if hrp and mySavedCFrame then
                hrp.CFrame = mySavedCFrame
                hrp.AssemblyLinearVelocity = Vector3.new(0, -1, 0)
            end
        end)
        startReturnHold(mySavedCFrame, BRING_RETURN_DURATION)
        task.wait(BRING_TELEPORT_WAIT)
        if not isManualGrabWindow() then
            pcall(function()
                if RS:FindFirstChild("StopCarry") then
                    RS.StopCarry:FireServer()
                end
            end)
        end
    end

    local function tryBringSequence(other, instantSkyMode, instantArg3Override)
        if bringBusy or SharedTeleportOwner then
            return false, "Another teleport sequence is running."
        end
        if os.clock() < SharedTeleportCooldownUntil then
            return false, "Waiting for previous teleport to finish syncing."
        end
        if not other or other == Player or not other.Parent or isBringProtected(other) then
            return false, "Player unavailable or whitelisted (protected from Bring)."
        end
        local hrp = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return false, "Your character is not ready." end
        if not RS:FindFirstChild("CarryRequest") then
            return false, "CarryRequest not found."
        end
        local evRoot = RS:FindFirstChild("EventInviteSystem")
        if not ((evRoot and evRoot:FindFirstChild("EventTeleportEvent")) or RS:FindFirstChild("EventTeleportEvent")) then
            return false, "EventTeleportEvent not found."
        end
        local savedCFrame = hrp.CFrame
        local a2, a3, a4
        if instantSkyMode then
            a2, a3, a4 = INSTANT_SKY_CARRY_ARG2, (instantArg3Override or INSTANT_SKY_CARRY_ARG3), 0
        else
            a2, a3, a4 = computeArgsForDesired(savedCFrame.Position, EVENT_CFRAME.Position)
        end
        bringBusy = true
        SharedTeleportOwner = "Bring"
        local ok, err = pcall(function()
            doBringOne(other, a2, a3, a4, savedCFrame)
        end)
        if SharedTeleportOwner == "Bring" then
            SharedTeleportOwner = nil
            SharedTeleportCooldownUntil = math.max(SharedTeleportCooldownUntil, os.clock() + 0.55)
        end
        bringBusy = false
        if not ok then return false, "Carry sequence failed locally: " .. tostring(err) end
        if instantSkyMode then
            return true, "Instant Sky request sent (args after target = 1, " .. tostring(a3) .. ", 0, 0, 0, 0); movement depends on the game server."
        end
        return true, "Bring request sent; movement depends on the game server."
    end
    local function resolveBringTarget(raw)
        local key = (raw or ""):match("^%s*(.-)%s*$"):lower():gsub("^@", "")
        if key == "" then return nil, "Enter a username, display name, part of a name, or ALL." end

        local candidates = {}
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= Player then
                local user = other.Name:lower()
                local display = other.DisplayName:lower()
                if user == key then
                    return other -- exact account username is unambiguous
                end
                local rank = nil
                if display == key then
                    rank = 1
                elseif user:sub(1, #key) == key or display:sub(1, #key) == key then
                    rank = 2
                elseif user:find(key, 1, true) or display:find(key, 1, true) then
                    rank = 3
                end
                if rank then
                    candidates[#candidates + 1] = { player = other, rank = rank }
                end
            end
        end

        local topRank = math.huge
        for _, entry in ipairs(candidates) do
            if entry.rank < topRank then topRank = entry.rank end
        end
        local best = {}
        for _, entry in ipairs(candidates) do
            if entry.rank == topRank then best[#best + 1] = entry.player end
        end
        if #best == 1 then return best[1] end
        if #best == 0 then return nil, "No online player matches '" .. key .. "'." end
        table.sort(best, function(a, b) return a.Name:lower() < b.Name:lower() end)
        local examples = {}
        for i = 1, math.min(#best, 4) do examples[#examples + 1] = best[i].Name end
        local suffix = #best > 4 and ", ..." or ""
        return nil, ("%d players match '%s': %s%s. Type more letters.")
            :format(#best, key, table.concat(examples, ", "), suffix)
    end
    local function gymbanEligible(other)
        return other ~= nil and other ~= Player and other.Parent == Players
            and not isBringProtected(other)
    end

    local function setGymbanUI(running)
        gymbanButton.Text = running and "GYMBAN: ON" or "GYMBAN: OFF"
        gymbanButton.BackgroundColor3 = running
            and Color3.fromRGB(30, 49, 46) or Color3.fromRGB(225, 231, 241)
        gymbanButton.TextColor3 = running
            and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(25, 30, 43)
    end

    local function clearGymbanListeners()
        for other, conn in pairs(gymbanConnections) do
            if conn then conn:Disconnect() end
            gymbanConnections[other] = nil
        end
        if gymbanAddedConnection then
            gymbanAddedConnection:Disconnect()
            gymbanAddedConnection = nil
        end
        if gymbanRemovingConnection then
            gymbanRemovingConnection:Disconnect()
            gymbanRemovingConnection = nil
        end
    end

    local function stopGymban(reason)
        gymbanRunning = false
        gymbanRevision += 1
        gymbanTarget = nil
        gymbanTargetName = nil
        gymbanAllMode = false
        clearGymbanListeners()
        table.clear(gymbanQueue)
        table.clear(gymbanScheduled)
        setGymbanUI(false)
        if reason and Gui.Parent then status.Text = reason end
    end

    local function scheduleGymban(other, character, revision)
        if not gymbanRunning or gymbanRevision ~= revision or not Gui.Parent
            or not gymbanEligible(other) or not character then return end
        if gymbanScheduled[other.UserId] == character then return end
        gymbanScheduled[other.UserId] = character
        gymbanQueue[#gymbanQueue + 1] = {player = other, character = character}

        if gymbanWorkerRevision == revision then return end
        gymbanWorkerRevision = revision
        task.spawn(function()
            while gymbanRunning and gymbanRevision == revision and Gui.Parent
                and #gymbanQueue > 0 do
                local entry = table.remove(gymbanQueue, 1)
                local target, spawnCharacter = entry.player, entry.character
                if gymbanScheduled[target.UserId] == spawnCharacter then
                    gymbanScheduled[target.UserId] = nil
                end
                local root = spawnCharacter:FindFirstChild("HumanoidRootPart")
                    or spawnCharacter:WaitForChild("HumanoidRootPart", 8)
                if root then
                    task.wait(GYMBAN_SPAWN_READY_DELAY)
                end
                if root and gymbanRunning and gymbanRevision == revision and Gui.Parent
                    and target.Character == spawnCharacter and gymbanEligible(target)
                    and (gymbanAllMode or target == gymbanTarget) then
                    local myChar = Player.Character
                    local myHumanoid = myChar and myChar:FindFirstChildOfClass("Humanoid")
                    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                    local sent, message = false, "Waiting for your respawn."
                    if myHumanoid and myHumanoid.Health > 0 and myRoot then
                        local remaining = GYMBAN_MIN_GLOBAL_INTERVAL - (os.clock() - lastGymbanRequestAt)
                        if remaining > 0 then task.wait(remaining) end
                        if gymbanRunning and gymbanRevision == revision and Gui.Parent
                            and target.Character == spawnCharacter and gymbanEligible(target)
                            and Player.Character == myChar and myHumanoid.Health > 0 then
                            lastGymbanRequestAt = os.clock()
                            sent, message = tryBringSequence(target, true)
                        end
                    end
                    if gymbanRunning and gymbanRevision == revision and Gui.Parent then
                        status.Text = sent and ("GYMBAN ON: repeating for " .. target.Name
                            .. " (continuous, rate-limited). Press OFF to stop.")
                            or ("GYMBAN ON: " .. tostring(message))
                    end
                    -- Always requeue the target while ON, including when our own
                    -- avatar is dead/unavailable. Its respawn is handled separately.
                    task.delay(GYMBAN_LOOP_INTERVAL, function()
                        if gymbanRunning and gymbanRevision == revision and Gui.Parent
                            and target.Character == spawnCharacter and gymbanEligible(target)
                            and (gymbanAllMode or target == gymbanTarget) then
                            local humanoid = spawnCharacter:FindFirstChildOfClass("Humanoid")
                            if humanoid and humanoid.Health > 0 then
                                scheduleGymban(target, spawnCharacter, revision)
                            end
                        end
                    end)
                end
                if gymbanRunning and gymbanRevision == revision and #gymbanQueue > 0 then
                    task.wait(GYMBAN_BETWEEN_TARGETS)
                end
            end
            if gymbanWorkerRevision == revision then gymbanWorkerRevision = nil end
        end)
    end

    local function watchGymbanPlayer(other, revision)
        if gymbanConnections[other] or not gymbanEligible(other) then return end
        gymbanConnections[other] = other.CharacterAdded:Connect(function(character)
            scheduleGymban(other, character, revision)
        end)
        if other.Character then
            scheduleGymban(other, other.Character, revision)
        end
    end

    persistentToggle(gymbanButton, function()
        if gymbanRunning then
            stopGymban("GYMBAN OFF. Already-sent requests cannot be recalled.")
            return
        end
        if sendingAll or bringBusy then
            status.Text = "Finish or cancel the current Bring request first."
            return
        end
        local targetText = (input.Text or ""):match("^%s*(.-)%s*$")
        local allMode = targetText:lower() == "all"
        local singleTarget = nil
        if not allMode then
            local problem
            singleTarget, problem = resolveBringTarget(targetText)
            if not singleTarget then
                status.Text = problem or "Enter a player name or ALL."
                return
            end
            if not gymbanEligible(singleTarget) then
                status.Text = "This player is protected by Whitelist or unavailable."
                return
            end
        end
        if not (Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")) then
            status.Text = "Your character is not ready."
            return
        end
        gymbanRunning = true
        gymbanRevision += 1
        local revision = gymbanRevision
        gymbanAllMode = allMode
        gymbanTarget = singleTarget
        gymbanTargetName = singleTarget and singleTarget.Name or nil
        lastGymbanRequestAt = -math.huge
        table.clear(gymbanQueue)
        table.clear(gymbanScheduled)
        setGymbanUI(true)
        status.Text = "GYMBAN ON: repeating INSTA across your respawns. Only OFF stops it."

        gymbanRemovingConnection = Players.PlayerRemoving:Connect(function(leaving)
            if gymbanConnections[leaving] then
                gymbanConnections[leaving]:Disconnect()
                gymbanConnections[leaving] = nil
            end
            if gymbanRunning and gymbanRevision == revision
                and not gymbanAllMode and leaving == gymbanTarget then
                gymbanTarget = nil
                status.Text = "GYMBAN ON: target left, waiting for rejoin (OFF stops)."
            end
        end)

        if allMode then
            for _, other in ipairs(Players:GetPlayers()) do
                watchGymbanPlayer(other, revision)
            end
            gymbanAddedConnection = Players.PlayerAdded:Connect(function(other)
                if gymbanRunning and gymbanRevision == revision then
                    watchGymbanPlayer(other, revision)
                end
            end)
        else
            watchGymbanPlayer(singleTarget, revision)
            gymbanAddedConnection = Players.PlayerAdded:Connect(function(other)
                if gymbanRunning and gymbanRevision == revision
                    and gymbanTargetName and other.Name == gymbanTargetName then
                    gymbanTarget = other
                    watchGymbanPlayer(other, revision)
                    status.Text = "GYMBAN ON: target rejoined, resuming."
                end
            end)
        end
    end)

    bring.Activated:Connect(function()
        if gymbanRunning then
            status.Text = "Turn GYMBAN OFF before using BRING."
            return
        end
        updateRules()
        local key = (input.Text or ""):match("^%s*(.-)%s*$"):lower()

        if sendingAll then
            activeRevision += 1
            sendingAll = false
            status.Text = "ALL queue cancelled. An already-sent Carry request cannot be recalled."
            return
        end
        if bringBusy then
            status.Text = "A Bring test is already running."
            return
        end

        if key == "all" then
            local targets = {}
            for _, other in ipairs(Players:GetPlayers()) do
                if shouldBringAllTarget(other) then
                    table.insert(targets, other)
                end
            end
            table.sort(targets, function(a, b) return a.Name:lower() < b.Name:lower() end)
            if #targets == 0 then
                status.Text = "No eligible Bring targets after Whitelist protection and Blacklist filtering."
                return
            end
            if not (Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")) then
                status.Text = "Your character is not ready."
                return
            end
            activeRevision += 1
            local rev = activeRevision
            sendingAll = true
            task.spawn(function()
                local completed, failed = 0, 0
                for _, other in ipairs(targets) do
                    if rev ~= activeRevision or not Gui.Parent then break end
                    if shouldBringAllTarget(other) then
                        local ok = tryBringSequence(other)
                        if ok then completed += 1 else failed += 1 end
                    end
                    if rev == activeRevision and Gui.Parent then
                        status.Text = ("ALL test sequences: %d sent, %d errors | %d selected. Press BRING to cancel queue.")
                            :format(completed, failed, #targets)
                    end
                end
                if rev == activeRevision then
                    sendingAll = false
                    if Gui.Parent then
                        status.Text = ("Batch finished: %d sequences sent, %d errors. Bring is NOT confirmed.")
                            :format(completed, failed)
                    end
                end
            end)
            return
        end

        local target, matchError = resolveBringTarget(input.Text)
        if not target then
            status.Text = matchError or "No matching player found."
            return
        end
        if isBringProtected(target) then
            status.Text = target.Name .. " is WHITELISTED: Bring request blocked."
            return
        end
        if not (Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")) then
            status.Text = "Your character is not ready."
            return
        end
        status.Text = "Testing Bring sequence for " .. target.Name .. " ..."
        task.spawn(function()
            local ok, message = tryBringSequence(target)
            if Gui.Parent then status.Text = target.Name .. ": " .. message end
        end)
    end)

    instantSky.Activated:Connect(function()
        if gymbanRunning then
            status.Text = "Turn GYMBAN OFF before using INSTA."
            return
        end
        if sendingAll or bringBusy then
            status.Text = "A Bring sequence is running. Try again once it finishes."
            return
        end
        local key = (input.Text or ""):match("^%s*(.-)%s*$"):lower()
        if key == "all" then
            status.Text = "INSTANT SKY is for one player only; ALL is disabled."
            return
        end
        local target, matchError = resolveBringTarget(input.Text)
        if not target then
            status.Text = matchError or "Enter one player's name."
            return
        end
        if isBringProtected(target) then
            status.Text = target.Name .. " is WHITELISTED: Instant Sky blocked."
            return
        end
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not targetRoot then
            status.Text = "Target's character is not ready."
            return
        end
        status.Text = "Trying INSTA for " .. target.Name .. " (Carry args 2/3/4 = 1, 400, 0) ..."
        task.spawn(function()
            local ok, message = tryBringSequence(target, true, INSTA_BUTTON_CARRY_ARG3)
            if Gui.Parent then
                status.Text = target.Name .. ": " .. message
            end
        end)
    end)

    clear.Activated:Connect(function()
        if gymbanRunning then
            status.Text = "Turn GYMBAN OFF before clearing the target."
            return
        end
        input.Text = ""
        status.Text = "Target cleared."
    end)

    Gui.Destroying:Connect(function()
        stopGymban()
        activeRevision += 1
        sendingAll = false
        if returnConn then returnConn:Disconnect() returnConn = nil end
    end)
    updateRules()
end

do
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Card = makeFeatureCard(DefensePage, "Anti Grab", 38)
    Card.Name = "DefenseAntiGrab"
    Card.Position = UDim2.fromOffset(0, 38)
    Card.Size = UDim2.fromOffset(430, 206)

    local Toggle = Instance.new("TextButton")
    Toggle.Name = "AntiGrabToggle"
    Toggle.Position = UDim2.fromOffset(16, 44)
    Toggle.Size = UDim2.fromOffset(180, 34)
    Toggle.Font = Enum.Font.GothamBold
    Toggle.TextSize = 12
    Toggle.AutoButtonColor = false
    Toggle.Parent = Card
    corner(Toggle, 8)

    local Status = Instance.new("TextLabel")
    Status.Name = "AntiGrabStatus"
    Status.Position = UDim2.fromOffset(16, 86)
    Status.Size = UDim2.fromOffset(398, 108)
    Status.BackgroundTransparency = 1
    Status.TextColor3 = Color3.fromRGB(40, 42, 55)
    Status.Font = Enum.Font.Gotham
    Status.TextSize = 12
    Status.TextWrapped = true
    Status.TextXAlignment = Enum.TextXAlignment.Left
    Status.TextYAlignment = Enum.TextYAlignment.Top
    Status.Parent = Card

    local enabled = false
    local alive = true
    local currentCharacter = nil
    local platformConnection = nil
    local grabConnections = {}
    local lastSafe = nil
    local lastSafeAt = -math.huge
    local lastAttempt = -math.huge
    local triggered = false
    local busy = false
    local sequence = 0
    local sampledTime = 0
    local safeWalkSpeed = nil
    local unstickUntil = 0
    local lastGetUpAt = -math.huge -- avoid restarting GettingUp every physics frame
    local note = "Waiting for your character to load..."
    local COOLDOWN = 0.20 -- limit server requests, not local movement recovery
    local RETURN_LOCK_SECONDS = 0.12 -- no prolonged position correction
    local RETURN_CORRECTION_GAP = 0.09
    local MAX_RETURN_CORRECTIONS = 1 -- never repeatedly snap the player backward
    local returnCorrections = 0
    local lastCorrectionAt = -math.huge
    local SAFE_POSITION_MAX_AGE = 1.25
    local TELEPORT_CORRECTION_DISTANCE = 9.0
    local returnCharacter = nil
    local returnCFrame = nil
    local returnUntil = 0
    local returnSequence = nil

    local function getTeleportEvent()
        local system = ReplicatedStorage:FindFirstChild("EventInviteSystem")
        local event = system and system:FindFirstChild("EventTeleportEvent")
        return event and event:IsA("RemoteEvent") and event or nil
    end

    local function cancelIncomingGrab()
        -- Prefer the game's dedicated release/decline requests.
        -- Never cancel our own active Carry -> Event TP -> StopCarry sequence.
        if SharedTeleportOwner ~= nil or isManualGrabWindow()
            or os.clock() < AntiTPIntentionalTeleportUntil then return false end
        local sent = false
        local stop = ReplicatedStorage:FindFirstChild("StopCarry")
        local decline = ReplicatedStorage:FindFirstChild("DeclineRequest")
        if stop and stop:IsA("RemoteEvent") then
            sent = pcall(function() stop:FireServer() end) or sent
        end
        if decline and decline:IsA("RemoteEvent") then
            sent = pcall(function() decline:FireServer() end) or sent
        end
        return sent
    end

    local function getParts()
        local c = Player.Character
        if not c then return nil end
        local h = c:FindFirstChildOfClass("Humanoid")
        local r = c:FindFirstChild("HumanoidRootPart")
        if not h or not r or h.Health <= 0 then return nil end
        return c, h, r
    end

    local function render()
        if not alive or not Gui.Parent then return end
        Toggle.Text = enabled and "ANTI GRAB: ON" or "ANTI GRAB: OFF"
        animateToggle(Toggle, enabled)
        local found = getTeleportEvent() ~= nil
        Status.Text = note .. "\nEventTeleportEvent: " .. (found and "FOUND" or "NOT FOUND") ..
            " | Triggers: Grab / Sit / Anchor." ..
            "\nImmediate movement release; no continuous position hold."
    end

    local function log(message, isError)
        note = message
        if isError then
            warn("[VOID HUB ANTI GRAB] " .. message)
        else
            print("[VOID HUB ANTI GRAB] " .. message)
        end
        render()
    end

    local function releaseMovement(h, r)
        -- Release immobilizing flags now, but don't continuously restart
        -- GettingUp (that transition can prevent normal movement itself).
        local wasHeld = h.PlatformStand or h.Sit or r.Anchored
        if h.PlatformStand then h.PlatformStand = false end
        if h.Sit then h.Sit = false end
        if r.Anchored then r.Anchored = false end
        if h.WalkSpeed < 0.5 then
            h.WalkSpeed = (safeWalkSpeed and safeWalkSpeed > 0.5)
                and safeWalkSpeed or 16
        end
        local state = h:GetState()
        local needsGetUp = wasHeld or state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.Ragdoll
            or state == Enum.HumanoidStateType.FallingDown
        local now = os.clock()
        if needsGetUp and now - lastGetUpAt >= 0.18 then
            lastGetUpAt = now
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
    end

    local function attemptReturn(c, destination)
        local active, humanoid, root = getParts()
        if active ~= c or not destination then return false end
        local ok, err = pcall(function()
            releaseMovement(humanoid, root)
            if (root.Position - destination.Position).Magnitude >= TELEPORT_CORRECTION_DISTANCE then
                c:PivotTo(destination)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)
        if not ok then warn("[VOID HUB ANTI GRAB] Return error: " .. tostring(err)) end
        return ok
    end

    local function clearReturnLock()
        returnCharacter = nil
        returnCFrame = nil
        returnUntil = 0
        returnSequence = nil
        returnCorrections = 0
        lastCorrectionAt = -math.huge
    end

    local function enforceReturnLock()
        if DeathTPIsEscaping or isManualGrabWindow() then
            clearReturnLock()
            unstickUntil = 0
            busy = false
            return
        end
        if not alive or not enabled then return end
        local now = os.clock()
        if now < unstickUntil then
            local c, h, r = getParts()
            if c == currentCharacter then
                -- Only touch movement state if the game reapplied a grab.
                if h.PlatformStand or h.Sit or r.Anchored then
                    pcall(function() releaseMovement(h, r) end)
                end
                if h.MoveDirection.Magnitude > 0.05
                    and h.WalkSpeed > 0.5 and not h.PlatformStand
                    and not h.Sit and not r.Anchored then
                    unstickUntil = 0
                    clearReturnLock()
                end
            end
        end
        if not returnCFrame then return end
        if Player.Character ~= returnCharacter or returnSequence ~= sequence then
            clearReturnLock()
            busy = false
            return
        end
        local _, h, r = getParts()
        if not h or not r then
            clearReturnLock()
            busy = false
            return
        end
        -- Never keep snapping the player back once they try to walk.
        -- Only a few spaced corrections are allowed while input is idle.
        if now >= returnUntil or returnCorrections >= MAX_RETURN_CORRECTIONS
            or (h.MoveDirection.Magnitude > 0.05
                and not h.PlatformStand and not h.Sit and not r.Anchored) then
            clearReturnLock()
            busy = false
            return
        end
        if (r.Position - returnCFrame.Position).Magnitude >= TELEPORT_CORRECTION_DISTANCE
            and now - lastCorrectionAt >= RETURN_CORRECTION_GAP then
            returnCorrections += 1
            lastCorrectionAt = now
            attemptReturn(returnCharacter, returnCFrame)
        end
    end

    local function reactToPlatformStand()
        if DeathTPIsEscaping or isManualGrabWindow()
            or SharedTeleportOwner ~= nil
            or os.clock() < AntiTPIntentionalTeleportUntil then return end
        if not alive or not enabled then return end
        local c, humanoid, root = getParts()
        if c ~= currentCharacter or not humanoid or not root then return end
        local grabbed = humanoid.PlatformStand or humanoid.Sit or root.Anchored
        if not grabbed then return end
        -- Critical: release movement BEFORE testing the remote cooldown/busy.
        -- Otherwise a second grab during cooldown could leave us stuck.
        pcall(function() releaseMovement(humanoid, root) end)
        local now = os.clock()
        if busy or now - lastAttempt < COOLDOWN then return end
        lastAttempt = now
        triggered = true
        -- A naked EventTeleportEvent on every grab can teleport our own
        -- avatar and fight the movement recovery. Use it only if the
        -- dedicated StopCarry/Decline requests do not exist or fail.
        unstickUntil = now + 0.20
        clearReturnLock()
        local released = cancelIncomingGrab()
        pcall(function() releaseMovement(humanoid, root) end)
        local freshSafe = lastSafe and now - lastSafeAt <= SAFE_POSITION_MAX_AGE
        local displaced = freshSafe
            and (root.Position - lastSafe.Position).Magnitude >= TELEPORT_CORRECTION_DISTANCE
        if displaced and humanoid.MoveDirection.Magnitude < 0.05 then
            attemptReturn(c, lastSafe) -- one correction, no return lock
        end
        -- EventTeleportEvent is a class/event teleport in this game, not a
        -- safe universal grab-cancel remote. Never fire it from Anti Grab.
        -- Otherwise completing a manual G grab can send US to a classroom.
        log(released and "Grab release sent. Walking stays unlocked."
            or "Local grab recovery attempted; no classroom TP fallback.")
    end

    local function attachCharacter(character)
        sequence += 1
        currentCharacter = character
        lastSafe = nil
        lastSafeAt = -math.huge
        sampledTime = 0
        safeWalkSpeed = nil
        unstickUntil = 0
        lastGetUpAt = -math.huge
        clearReturnLock()
        busy = false
        triggered = false
        if platformConnection then
            platformConnection:Disconnect()
            platformConnection = nil
        end
        for _, conn in ipairs(grabConnections) do conn:Disconnect() end
        table.clear(grabConnections)
        task.spawn(function()
            local humanoid = character:WaitForChild("Humanoid", 10)
            local root = character:WaitForChild("HumanoidRootPart", 10)
            if not alive or Player.Character ~= character or not humanoid or not root then return end
            platformConnection = humanoid:GetPropertyChangedSignal("PlatformStand"):Connect(function()
                if not humanoid.PlatformStand then triggered = false end
                reactToPlatformStand()
            end)
            -- Some games apply Sit/Anchored instead of PlatformStand to hold
            -- a carried character. Detect those without waiting for polling.
            table.insert(grabConnections, humanoid:GetPropertyChangedSignal("Sit"):Connect(reactToPlatformStand))
            table.insert(grabConnections, root:GetPropertyChangedSignal("Anchored"):Connect(reactToPlatformStand))
            log("Character ready; watching Grab, Sit and Anchor states.")
            reactToPlatformStand()
        end)
    end

    persistentToggle(Toggle, function()
        enabled = not enabled
        sequence += 1
        clearReturnLock()
        busy = false
        triggered = false
        lastSafe, lastSafeAt = nil, -math.huge
        sampledTime = 0
        unstickUntil = 0
        lastGetUpAt = -math.huge
        log(enabled and "Anti-Grab enabled. Fast recovery ready." or "Anti-Grab disabled.")
    end)

    bindGlobal(Player.CharacterAdded, attachCharacter)
    if Player.Character then attachCharacter(Player.Character) end

    bindGlobal(RunService.Heartbeat, function(dt)
        enforceReturnLock()
        if not alive or not enabled then return end
        local c, h, r = getParts()
        if not c or c ~= currentCharacter then return end
        -- Server may reapply a grab after a local release; retry getting up on
        -- the very next Heartbeat instead of staying frozen until cooldown.
        if not SharedTeleportOwner and not isManualGrabWindow()
            and os.clock() >= AntiTPIntentionalTeleportUntil
            and (h.PlatformStand or h.Sit or r.Anchored) then
            reactToPlatformStand()
            pcall(function() releaseMovement(h, r) end)
        end
        sampledTime += dt
        if sampledTime < 0.045 then return end
        sampledTime = 0
        if not busy and not h.PlatformStand and not h.Sit
            and h.FloorMaterial ~= Enum.Material.Air and not r.Anchored
            and r.Position.Y > workspace.FallenPartsDestroyHeight + 50
            and r.AssemblyLinearVelocity.Magnitude < 85 then
            lastSafe = c:GetPivot()
            lastSafeAt = os.clock()
            if h.WalkSpeed > 0.5 then safeWalkSpeed = h.WalkSpeed end
        end
    end)

    Gui.Destroying:Connect(function()
        alive = false
        enabled = false
        sequence += 1
        unstickUntil = 0
        clearReturnLock()
        if platformConnection then
            platformConnection:Disconnect()
            platformConnection = nil
        end
        for _, conn in ipairs(grabConnections) do conn:Disconnect() end
        table.clear(grabConnections)
    end)
    render()
end

-- =====================================================================
-- DEFENSE: ANTI TP (SELF ONLY) - V110 GRAB TELEPORT RETURN
-- Unlike V109 this does not depend on one classroom's spawn coordinates,
-- being >260 studs from that room, or a fresh (<5 second) safe snapshot.
-- Detects abrupt unexplained self-position jumps and performs bounded local
-- return attempts. Does not intercept/block another player's server action.
-- Explicit VOID HUB Bring/INSTA actions are excluded via the shared marker.
-- =====================================================================
do
    local card = makeFeatureCard(DefensePage, "Anti TP", 620)
    card.Name = "DefenseAntiTP"
    card.Size = UDim2.fromOffset(880, 177)

    local toggle = Instance.new("TextButton")
    toggle.Name = "AntiTPToggle"
    toggle.Position = UDim2.fromOffset(16, 47)
    toggle.Size = UDim2.fromOffset(210, 38)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "AntiTPStatus"
    status.Position = UDim2.fromOffset(240, 42)
    status.Size = UDim2.fromOffset(622, 70)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.TextSize = 12
    status.Font = Enum.Font.Gotham
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    status.Parent = card

    local details = Instance.new("TextLabel")
    details.Name = "AntiTPDetails"
    details.Position = UDim2.fromOffset(16, 121)
    details.Size = UDim2.fromOffset(844, 46)
    details.BackgroundTransparency = 1
    details.TextColor3 = Color3.fromRGB(85, 88, 104)
    details.TextSize = 11
    details.Font = Enum.Font.Gotham
    details.TextWrapped = true
    details.TextXAlignment = Enum.TextXAlignment.Left
    details.TextYAlignment = Enum.TextYAlignment.Top
    details.Text = "Attempts to restore your last safe spot after a sudden forced self-teleport. " ..
        "Large intentional teleports from outside VOID HUB may also be reversed. Server may override returns."
    details.Parent = card

    -- Optional secondary clue from the user's Bring.txt. The main detector
    -- intentionally works even when the classroom is somewhere else.
    local EXPECTED_EVENT_AREA = Vector3.new(53.5, 8.298911, 118.149994)
    local MIN_SUDDEN_JUMP = 52
    local MIN_CLASSROOM_JUMP = 22
    local SAFE_MAX_AGE = 30
    local RETURN_GAP = 1.35
    local SAFE_SAMPLE_INTERVAL = 0.08
    local enabled, alive = false, true
    local trackedCharacter = nil
    local lastPos, lastPosAt = nil, nil
    local savedPivot, savedAt = nil, -math.huge
    local sampleClock, lastRescue = 0, -math.huge
    local rescueRevision = 0
    local rescueUntil = 0
    local note = "OFF. Normal teleports are unchanged."

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "ANTI TP: ON" or "ANTI TP: OFF"
        animateToggle(toggle, enabled)
        status.Text = note
    end

    local function resetTracking(character)
        trackedCharacter = character
        lastPos, lastPosAt = nil, nil
        savedPivot, savedAt = nil, -math.huge
        sampleClock = 0
        rescueUntil = 0
        rescueRevision += 1
    end

    local function followIsActive()
        local p = pages["Movement"]
        local c = p and p:FindFirstChild("MovementFollow")
        local btn = c and c:FindFirstChild("FollowToggle")
        return btn and btn:IsA("TextButton") and btn.Text == "FOLLOW: ON"
    end

    local function getParts(c)
        if not c or c ~= Player.Character then return nil, nil end
        local h = c:FindFirstChildOfClass("Humanoid")
        local r = c:FindFirstChild("HumanoidRootPart")
        if not h or not r or h.Health <= 0 then return nil, nil end
        return h, r
    end

    local function isValidGround(c, h, r)
        if h.PlatformStand or h.Sit or r.Anchored
            or h.FloorMaterial == Enum.Material.Air
            or r.Position.Y < workspace.FallenPartsDestroyHeight + 40
            or r.AssemblyLinearVelocity.Magnitude > 140 then
            return false
        end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {c}
        local hit = workspace:Raycast(r.Position + Vector3.new(0, 1, 0),
            Vector3.new(0, -11, 0), params)
        return hit and hit.Instance and hit.Instance.CanCollide or false
    end

    local function tryReturn(c, destination, rev)
        if not alive or not enabled or not Gui.Parent
            or Player.Character ~= c or rescueRevision ~= rev
            or not destination or DeathTPIsEscaping then return end
        local h, r = getParts(c)
        if not h or not r then return end
        if (r.Position - destination.Position).Magnitude < 7 then return end
        local ok, err = pcall(function()
            if h.Sit then h.Sit = false end
            if h.PlatformStand then
                h.PlatformStand = false
                h:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
            c:PivotTo(destination)
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end)
        if not ok then
            note = "Anti TP return error: " .. tostring(err)
            warn("[VOID HUB ANTI TP] " .. note)
            render()
        end
    end

    local function beginReturn(c, destination, distance)
        lastRescue = os.clock()
        rescueUntil = lastRescue + 1.55
        rescueRevision += 1
        local rev = rescueRevision
        note = ("Sudden teleport (%.0f studs) detected. Returning to saved spot...")
            :format(distance)
        render()
        tryReturn(c, destination, rev)
        -- Bounded correction of delayed server motion, NOT a continuous snap loop.
        for _, delaySeconds in ipairs({0.08, 0.20, 0.40, 0.72, 1.10, 1.48}) do
            task.delay(delaySeconds, function()
                tryReturn(c, destination, rev)
                if delaySeconds == 1.48 and alive and enabled
                    and rescueRevision == rev then
                    rescueUntil = 0
                    note = "Return attempted. A server teleport may still override it."
                    render()
                end
            end)
        end
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        resetTracking(Player.Character)
        note = enabled and "ON. Step on solid ground to save your pre-grab position."
            or "OFF. Normal teleports are unchanged."
        render()
    end)

    bindGlobal(Player.CharacterAdded, function(c)
        resetTracking(c)
        if enabled then
            note = "ON. Respawned; recording a new safe position."
            render()
        end
    end)

    bindGlobal(RunService.Heartbeat, function(dt)
        if not alive or not enabled or not Gui.Parent then return end
        local c = Player.Character
        if c ~= trackedCharacter then resetTracking(c) end
        local h, r = getParts(c)
        if not h then
            lastPos, lastPosAt = nil, nil
            return
        end
        local now, pos = os.clock(), r.Position
        local previousPos, previousAt = lastPos, lastPosAt
        lastPos, lastPosAt = pos, now

        -- These features deliberately move the local player. Ignoring them
        -- prevents fighting your own Bring, INSTA, Follow and Death TP tools.
        if DeathTPIsEscaping or followIsActive() or isManualGrabWindow()
            or now < AntiTPIntentionalTeleportUntil then
            return
        end

        if now < rescueUntil then
            return -- do not overwrite the saved pre-teleport position
        end

        if previousPos and previousAt and savedPivot
            and now - savedAt < SAFE_MAX_AGE
            and now - lastRescue >= RETURN_GAP then
            local elapsed = math.max(now - previousAt, 1 / 240)
            local distance = (pos - previousPos).Magnitude
            -- Detect unusual displacement at faster-than-walking speed.
            -- The time-aware threshold avoids flagging high TP Walk values
            -- during a short frame-rate stall.
            local abrupt = distance >= math.max(MIN_SUDDEN_JUMP, 1000 * elapsed)
            local nearEvent = (pos - EXPECTED_EVENT_AREA).Magnitude < 210
                and (previousPos - EXPECTED_EVENT_AREA).Magnitude > 250
                and distance >= math.max(MIN_CLASSROOM_JUMP, 850 * elapsed)
            if abrupt or nearEvent then
                local destination = savedPivot
                beginReturn(c, destination, distance)
                lastPos, lastPosAt = r.Position, os.clock()
                return
            end
        end

        sampleClock += math.max(0, dt)
        if sampleClock >= SAFE_SAMPLE_INTERVAL then
            sampleClock = 0
            if isValidGround(c, h, r) then
                savedPivot = c:GetPivot()
                savedAt = now
            end
        end
    end)

    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        rescueRevision += 1
    end)
    render()
end

-- Anti Void supplied by the user, integrated as a private module with panel lifecycle cleanup.
do
    local AntiVoid = (function()
-- VOID HUB V82 | stronger ground-validated, predictive Anti Void.
-- Local character rescue only. Server correction and server-side death still win.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local me = Players.LocalPlayer

local antiVoidEnabled = false
local heartbeatConn, charAddedConn = nil, nil
local setupGeneration = 0
local lastGroundedPivot, lastGroundedRootPosition = nil, nil
local fallStartedAt, lastRescueAt = nil, -math.huge
local emergencyUsed = false

local SAMPLE_INTERVAL = 0.12
local CHECK_INTERVAL = 0.06
local VOID_MARGIN = 65             -- earlier than V81's +15
local PREDICTION_SECONDS = 0.45   -- anticipate fast downward movement
local FAST_FALL_DURATION = 0.85   -- avoid rescuing on ordinary jumps
local FAST_FALL_DISTANCE = 38
local FAST_FALL_SPEED = -65
local RESCUE_COOLDOWN = 0.35      -- bounded retry if the server moves us back down

local function disconnectHeartbeat()
    if heartbeatConn then
        heartbeatConn:Disconnect()
        heartbeatConn = nil
    end
end

local function clearSavedSpot()
    lastGroundedPivot = nil
    lastGroundedRootPosition = nil
    fallStartedAt = nil
    lastRescueAt = -math.huge
    emergencyUsed = false
end

local function raycastDown(character, origin, length)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character}
    params.IgnoreWater = true
    local hit = Workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
    if hit and hit.Instance and hit.Instance.CanCollide then
        return hit
    end
    return nil
end

local function validGround(character, humanoid, root, voidLimit)
    if humanoid.Health <= 0 or humanoid.PlatformStand or humanoid.Sit then return false end
    if humanoid.FloorMaterial == Enum.Material.Air or root.Anchored then return false end
    if root.Position.Y < voidLimit + 25 then return false end
    if math.abs(root.AssemblyLinearVelocity.Y) > 35 then return false end
    -- Don't store temporary floor-state reports while actually over open space.
    return raycastDown(character, root.Position + Vector3.new(0, 1.5, 0), 10) ~= nil
end

local function stopDownwardMotion(character)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and not part.Anchored then
            part.AssemblyLinearVelocity = Vector3.zero
            part.AssemblyAngularVelocity = Vector3.zero
        end
    end
end

local function findEmergencySpawn(root)
    local best, bestDist = nil, math.huge
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("SpawnLocation") and obj.Enabled then
            local dist = (obj.Position - root.Position).Magnitude
            if dist < bestDist then
                best, bestDist = obj, dist
            end
        end
    end
    return best
end

local function rescue(character, root, voidLimit)
    local now = os.clock()
    if now - lastRescueAt < RESCUE_COOLDOWN then return end
    lastRescueAt = now

    local destination
    if lastGroundedPivot and lastGroundedRootPosition then
        -- A saved platform may have moved or disappeared; validate before returning.
        local hit = raycastDown(character, lastGroundedRootPosition + Vector3.new(0, 1.5, 0), 11)
        if hit then
            destination = lastGroundedPivot * CFrame.new(0, 3, 0)
        end
    end

    if not destination then
        -- When enabled mid-fall, no valid grounded position may have been captured.
        -- A real spawn pad is preferable to repeatedly bouncing over empty space.
        local spawnPad = findEmergencySpawn(root)
        if spawnPad then
            destination = spawnPad.CFrame * CFrame.new(0, 6, 0)
        elseif not emergencyUsed then
            -- One last-chance lift only; this is NOT a guaranteed landing spot.
            emergencyUsed = true
            destination = CFrame.new(root.Position.X, math.max(root.Position.Y + 45, voidLimit + 65), root.Position.Z)
        else
            return
        end
    end

    pcall(function()
        character:PivotTo(destination)
        stopDownwardMotion(character)
    end)
    fallStartedAt = nil
end

local function setupCharacter(character, generation)
    if not antiVoidEnabled or not character or generation ~= setupGeneration then return end
    local humanoid = character:WaitForChild("Humanoid", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    if not antiVoidEnabled or generation ~= setupGeneration or me.Character ~= character
        or not humanoid or not root then return end

    disconnectHeartbeat()
    clearSavedSpot()
    local checkElapsed, saveElapsed = 0, SAMPLE_INTERVAL

    heartbeatConn = RunService.Heartbeat:Connect(function(dt)
        if not antiVoidEnabled or generation ~= setupGeneration
            or me.Character ~= character or not character.Parent or not root.Parent then return end
        if humanoid.Health <= 0 or DeathTPIsEscaping then return end
        checkElapsed += dt
        saveElapsed += dt
        if checkElapsed < CHECK_INTERVAL then return end
        checkElapsed = 0

        local voidLimit = Workspace.FallenPartsDestroyHeight
        local grounded = validGround(character, humanoid, root, voidLimit)
        if grounded then
            fallStartedAt = nil
            if saveElapsed >= SAMPLE_INTERVAL then
                lastGroundedPivot = character:GetPivot()
                lastGroundedRootPosition = root.Position
                saveElapsed = 0
            end
            return
        end

        local vy = root.AssemblyLinearVelocity.Y
        local y = root.Position.Y
        local now = os.clock()
        if vy < -12 then
            fallStartedAt = fallStartedAt or now
        elseif vy >= -2 then
            fallStartedAt = nil
        end

        -- Predict crossing of the void boundary before Roblox destroys the parts.
        local predictedY = y + math.min(vy, 0) * PREDICTION_SECONDS
            - 0.5 * Workspace.Gravity * (PREDICTION_SECONDS ^ 2)
        local nearVoid = y <= voidLimit + VOID_MARGIN
            or predictedY <= voidLimit + VOID_MARGIN

        -- Recover a sustained, fast fall well above the actual void boundary.
        -- Skip recovery if a solid floor is directly below us.
        local fallingIntoGap = false
        if lastGroundedRootPosition and fallStartedAt
            and now - fallStartedAt >= FAST_FALL_DURATION
            and vy < FAST_FALL_SPEED
            and y < lastGroundedRootPosition.Y - FAST_FALL_DISTANCE then
            fallingIntoGap = raycastDown(character, root.Position, 48) == nil
        end

        if nearVoid or fallingIntoGap then
            rescue(character, root, voidLimit)
        end
    end)
end

local function enableAntiVoid()
    if antiVoidEnabled then return end
    antiVoidEnabled = true
    setupGeneration += 1
    local generation = setupGeneration
    if me.Character then task.spawn(setupCharacter, me.Character, generation) end
    if charAddedConn then charAddedConn:Disconnect() end
    charAddedConn = me.CharacterAdded:Connect(function(character)
        setupGeneration += 1
        local nextGeneration = setupGeneration
        disconnectHeartbeat()
        clearSavedSpot()
        task.spawn(setupCharacter, character, nextGeneration)
    end)
end

local function disableAntiVoid()
    if not antiVoidEnabled then return end
    antiVoidEnabled = false
    setupGeneration += 1
    disconnectHeartbeat()
    if charAddedConn then
        charAddedConn:Disconnect()
        charAddedConn = nil
    end
    clearSavedSpot()
end

return {
    Enable = enableAntiVoid,
    Disable = disableAntiVoid,
    Toggle = function()
        if antiVoidEnabled then disableAntiVoid() else enableAntiVoid() end
        return antiVoidEnabled
    end,
    IsEnabled = function() return antiVoidEnabled end,
}

    end)()
    local card = makeFeatureCard(DefensePage, "Anti Void", 260)
    card.Name = "DefenseAntiVoid"
    card.Position = UDim2.fromOffset(0, 260)
    card.Size = UDim2.fromOffset(430, 172)
    local toggle = Instance.new("TextButton")
    toggle.Position = UDim2.fromOffset(16, 44)
    toggle.Size = UDim2.fromOffset(110, 34)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.Text = "OFF"
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)
    animateToggle(toggle, false)
    local description = Instance.new("TextLabel")
    description.Position = UDim2.fromOffset(16, 88)
    description.Size = UDim2.fromOffset(398, 72)
    description.BackgroundTransparency = 1
    description.TextColor3 = Color3.fromRGB(40, 42, 55)
    description.Font = Enum.Font.Gotham
    description.TextSize = 12
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.Text = "Checks solid ground every 0.12s. Predicts deep falls early, then returns to the last safe spot and stops falling speed. Respawn-safe; server corrections may still override."
    description.Parent = card
    persistentToggle(toggle, function()
        local on = AntiVoid.Toggle()
        toggle.Text = on and "ON" or "OFF"
        animateToggle(toggle, on)
    end)
    Gui.Destroying:Connect(function()
        AntiVoid.Disable()
    end)
end

-- =====================================================================
-- ANTI RAGDOLL V13 - LOCAL GET-UP ONLY, NO CLASS TELEPORT
-- Never fire EventTeleportEvent while recovering from knockdown.
-- The game's server can send the player to a classroom on that request.
-- =====================================================================
do
    local card = makeFeatureCard(DefensePage, "Anti Ragdoll", 38)
    card.Name = "DefenseAntiRagdoll"
    card.Position = UDim2.fromOffset(450, 38)
    card.Size = UDim2.fromOffset(430, 206)

    local toggle = Instance.new("TextButton")
    toggle.Name = "AntiRagdollToggle"
    toggle.Position = UDim2.fromOffset(16, 44)
    toggle.Size = UDim2.fromOffset(220, 34)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    corner(toggle, 8)
    toggle.Parent = card

    local status = Instance.new("TextLabel")
    status.Name = "AntiRagdollStatus"
    status.Position = UDim2.fromOffset(16, 87)
    status.Size = UDim2.fromOffset(398, 107)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Font = Enum.Font.Gotham
    status.Parent = card

    local knockdown = {
        [Enum.HumanoidStateType.Ragdoll] = true,
        [Enum.HumanoidStateType.FallingDown] = true,
        [Enum.HumanoidStateType.Physics] = true,
    }
    local RETURN_DELAY = 0.025  -- 25ms; task scheduler timing is not exact.
    local RETURN_LOCK_SECONDS = 0.75 -- bounded correction, no movement locking
    local COOLDOWN = 1.1 -- don't flood server event
    local SAFE_AGE = 4.0 -- longer window for grounded recovery
    local enabled, alive = false, true
    local character, humanoid, root
    local charConnections = {}
    local revision = 0
    local inRecovery = false
    local recoveryGeneration = 0
    local returnCFrame = nil
    local returnCharacter = nil
    local returnUntil = 0
    local returnBegin = 0
    local safeCFrame, safeAt = nil, -math.huge
    local lastRequest = -math.huge
    local sampled = 0
    local returnCorrections = 0
    local lastCorrectionAt = -math.huge
    local recoveries = 0
    local message = "OFF: local ragdoll recovery disabled."

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "ANTI RAGDOLL: ON" or "ANTI RAGDOLL: OFF"
        animateToggle(toggle, enabled)
        status.Text = message ..
            "\nDetects Ragdoll / Physics / FallingDown, including immobilized states." ..
            "\nLocal getting-up works without the teleport event; server rules still apply."
    end

    local function stopReturn()
        recoveryGeneration += 1
        inRecovery = false
        returnCFrame, returnCharacter = nil, nil
        returnUntil, returnBegin = 0, 0
        returnCorrections = 0
    end

    local function detach()
        stopReturn()
        for _, conn in ipairs(charConnections) do conn:Disconnect() end
        table.clear(charConnections)
        character, humanoid, root = nil, nil, nil
        safeCFrame, safeAt = nil, -math.huge
        sampled = 0
    end

    local function validForReturn(c)
        return alive and enabled and c == Player.Character and c == character
            and returnCharacter == c and c.Parent
            and humanoid and humanoid.Parent and humanoid.Health > 0
            and root and root.Parent
    end

    local function forceReturn()
        if DeathTPIsEscaping or isManualGrabWindow() then
            if inRecovery then stopReturn() end
            return
        end
        if not inRecovery or not returnCFrame then return end
        local c = returnCharacter
        if not validForReturn(c) then stopReturn() return end
        local now = os.clock()
        if now >= returnUntil then
            stopReturn()
            message = "Event return window complete #" .. tostring(recoveries)
            render()
            return
        end
        if now < returnBegin then return end
        -- Fix: do not PivotTo every rendered frame. Return only on an actual
        -- large displacement, with a maximum of 3 bounded corrections.
        if now - lastCorrectionAt >= 0.12 and returnCorrections < 3
            and (root.Position - returnCFrame.Position).Magnitude > 8 then
            lastCorrectionAt = now
            returnCorrections += 1
            pcall(function()
                c:PivotTo(returnCFrame)
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end)
        end
    end

    local function rememberGrounded()
        if not enabled or inRecovery or not character or not humanoid or not root
            or Player.Character ~= character or humanoid.Health <= 0 then return end
        if humanoid.PlatformStand or humanoid.Sit or root.Anchored then return end
        if knockdown[humanoid:GetState()] or humanoid.FloorMaterial == Enum.Material.Air then return end
        if root.Position.Y < workspace.FallenPartsDestroyHeight + 35 then return end
        if root.AssemblyLinearVelocity.Magnitude > 75 then return end
        safeCFrame, safeAt = character:GetPivot(), os.clock()
    end

    local function recover(c, h, r, currentRevision)
        if DeathTPIsEscaping or isManualGrabWindow() then return end
        if not enabled or not alive or inRecovery or c ~= Player.Character
            or h.Health <= 0 or r.Anchored then return end
        -- Pure PlatformStand is handled by Anti Grab. In an actual Ragdoll /
        -- Physics state, however, PlatformStand must not block recovery.
        if h.PlatformStand and not knockdown[h:GetState()] then return end
        local now = os.clock()
        if now - lastRequest < COOLDOWN then return end
        lastRequest = now
        local destination = (safeCFrame and now - safeAt <= SAFE_AGE)
            and safeCFrame or c:GetPivot()
        inRecovery = true
        recoveryGeneration += 1
        local thisGeneration = recoveryGeneration
        returnCFrame, returnCharacter = destination, c
        returnBegin = now + RETURN_DELAY
        returnUntil = now + RETURN_LOCK_SECONDS
        returnCorrections = 0

        -- GettingUp also works when this game's remote has been renamed,
        -- blocked, or removed; don't gate all recovery on one RemoteEvent.
        pcall(function()
            h.PlatformStand = false
            h.Sit = false
            r.AssemblyAngularVelocity = Vector3.zero
            h:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
        -- Local get-up only; no class/event teleport remote.
        recoveries += 1
        message = "Local ragdoll recovery (no class teleport) #" .. tostring(recoveries)
        render()

        task.delay(RETURN_DELAY, function()
            if currentRevision ~= revision or thisGeneration ~= recoveryGeneration then return end
            forceReturn()
            if validForReturn(c) then
                pcall(function()
                    h.PlatformStand = false
                    h.Sit = false
                    h:ChangeState(Enum.HumanoidStateType.GettingUp)
                end)
            end
        end)
    end

    local function attachCharacter(c)
        if not enabled or not c or c ~= Player.Character then return end
        revision += 1
        local mine = revision
        detach()
        local h = c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid", 10)
        local r = c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 10)
        if not enabled or mine ~= revision or c ~= Player.Character or not h or not r then return end
        character, humanoid, root = c, h, r
        rememberGrounded()
        message = "ON: monitoring ragdoll; saving grounded positions."
        render()
        table.insert(charConnections, h.StateChanged:Connect(function(_, newState)
            if mine ~= revision or not enabled then return end
            if knockdown[newState] then recover(c, h, r, mine) end
        end))
        table.insert(charConnections, h:GetPropertyChangedSignal("PlatformStand"):Connect(function()
            if mine ~= revision or not enabled then return end
            if h.PlatformStand and knockdown[h:GetState()] then
                recover(c, h, r, mine)
            end
        end))
        if knockdown[h:GetState()] then recover(c, h, r, mine) end
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        revision += 1
        detach()
        if enabled then
            message = "Enabling local get-up recovery; no teleport event."
            if Player.Character then task.spawn(attachCharacter, Player.Character) end
        else
            message = "OFF: recovery stopped."
        end
        render()
    end)
    bindGlobal(Player.CharacterAdded, function(c)
        if enabled then task.spawn(attachCharacter, c) end
    end)
    bindGlobal(RunService.RenderStepped, forceReturn)
    bindGlobal(RunService.Heartbeat, function(dt)
        forceReturn()
        if not alive or not enabled or inRecovery then return end
        sampled += dt
        if sampled < 0.06 then return end
        sampled = 0
        if humanoid and knockdown[humanoid:GetState()] then
            recover(character, humanoid, root, revision)
        end
        rememberGrounded()
    end)
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        revision += 1
        detach()
    end)
    render()
end

-- =====================================================================
-- DEATH TP (SELF ONLY) - RESPAWN NEAR WHERE YOU DIED
-- Save the original character's last position at death, then restore the
-- NEW character there after the normal respawn. Does NOT use ClassTeleportEvent
-- or EventTeleportEvent; no HP threshold or permanent polling loop.
-- =====================================================================
do
    local card = makeFeatureCard(DefensePage, "Death TP", 260)
    card.Name = "DefenseDeathTP"
    card.Position = UDim2.fromOffset(450, 260)
    card.Size = UDim2.fromOffset(430, 146)

    local toggle = Instance.new("TextButton")
    toggle.Name = "DeathTPToggle"
    toggle.Position = UDim2.fromOffset(16, 44)
    toggle.Size = UDim2.fromOffset(210, 34)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "DeathTPStatus"
    status.Position = UDim2.fromOffset(16, 86)
    status.Size = UDim2.fromOffset(398, 48)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.TextSize = 11
    status.Font = Enum.Font.Gotham
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = card

    local enabled = false
    local alive = true
    local revision = 0
    local deathPosition = nil
    local diedConnection = nil
    local healthConnection = nil
    local note = "OFF. Respawn normally."

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "DEATH TP: ON" or "DEATH TP: OFF"
        animateToggle(toggle, enabled)
        status.Text = note .. "\nMoves only your new character; server may override the return."
    end

    local function disconnectCharacter()
        if diedConnection then diedConnection:Disconnect(); diedConnection = nil end
        if healthConnection then healthConnection:Disconnect(); healthConnection = nil end
    end

    local function saveDeathPosition(c, root, h)
        if not enabled or not alive or c ~= Player.Character then return end
        if deathPosition then return end
        if not root or not root.Parent then return end
        -- Capture at death, before the corpse may fall or be cleaned up.
        deathPosition = root.CFrame
        note = "Death spot saved. Waiting for respawn..."
        render()
    end

    local function attachToCharacter(c)
        if not enabled or not alive or c ~= Player.Character then return end
        revision += 1
        local myRevision = revision
        disconnectCharacter()

        local h = c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid", 8)
        local root = c:FindFirstChild("HumanoidRootPart") or c:WaitForChild("HumanoidRootPart", 8)
        if not enabled or not alive or myRevision ~= revision
            or c ~= Player.Character or not h or not root then return end

        diedConnection = h.Died:Connect(function()
            if myRevision == revision then
                saveDeathPosition(c, root, h)
            end
        end)
        -- Backup when health hits zero before the Died event.
        healthConnection = h.HealthChanged:Connect(function(health)
            if health <= 0 and myRevision == revision then
                saveDeathPosition(c, root, h)
            end
        end)

        if deathPosition then
            local destination = deathPosition + Vector3.new(0, 2.5, 0)
            deathPosition = nil
            note = "Respawn detected. Returning near death spot..."
            render()
            -- Give Roblox's normal respawn placement a brief chance to finish.
            task.delay(0.2, function()
                if not enabled or not alive or myRevision ~= revision
                    or c ~= Player.Character or not root.Parent or h.Health <= 0 then return end
                local ok, err = pcall(function()
                    c:PivotTo(destination)
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
                if ok then
                    note = "Return attempted near death spot."
                    -- Exactly one follow-up if normal spawn handling moved us elsewhere.
                    task.delay(0.28, function()
                        if not enabled or not alive or myRevision ~= revision
                            or c ~= Player.Character or not root.Parent or h.Health <= 0 then return end
                        if (root.Position - destination.Position).Magnitude > 12 then
                            pcall(function() c:PivotTo(destination) end)
                        end
                    end)
                else
                    note = "Return failed: " .. tostring(err)
                    warn("[VOID HUB Death TP] " .. note)
                end
                render()
            end)
        else
            note = "ON. Your next respawn will return near where you died."
            render()
        end
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        revision += 1
        disconnectCharacter()
        deathPosition = nil
        if enabled then
            note = "ON. Waiting for death."
            if Player.Character then task.spawn(attachToCharacter, Player.Character) end
        else
            note = "OFF. Normal respawn."
        end
        render()
    end)

    bindGlobal(Player.CharacterAdded, function(c)
        if enabled then task.spawn(attachToCharacter, c) end
    end)
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        revision += 1
        deathPosition = nil
        disconnectCharacter()
    end)
    render()
end

-- =====================================================================
-- DEFENSE: AUTO BLOCK (V162) - LOCAL AUTO POSE + PHYSICAL F HANDOFF
-- Keep proven V156 F tap timing and Heartbeat scheduling.
-- Fade auto-sourced F animation immediately and on every render frame.
-- When the user holds F, transfer F ownership instead of dropping a
-- synthetic key and blocking the actual manual F input.
-- Manual G and punches are never visually suppressed by Auto Block.
-- Server decides whether blocking is successful; this cannot prevent all damage.
-- Same ON/OFF toggle; all other Defense/Attack features unchanged.
-- =====================================================================
do
    local card = makeFeatureCard(DefensePage, "Auto Block", 448)
    card.Name = "DefenseAutoBlock"
    card.Position = UDim2.fromOffset(0, 448)
    card.Size = UDim2.fromOffset(880, 152)

    local toggle = Instance.new("TextButton")
    toggle.Name = "AutoBlockToggle"
    toggle.Position = UDim2.fromOffset(16, 47)
    toggle.Size = UDim2.fromOffset(205, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "AutoBlockStatus"
    status.Position = UDim2.fromOffset(240, 44)
    status.Size = UDim2.fromOffset(621, 45)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.TextSize = 12
    status.Font = Enum.Font.Gotham
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    status.Parent = card

    local details = Instance.new("TextLabel")
    details.Name = "AutoBlockDetails"
    details.Position = UDim2.fromOffset(240, 98)
    details.Size = UDim2.fromOffset(620, 43)
    details.BackgroundTransparency = 1
    details.TextColor3 = Color3.fromRGB(85, 88, 104)
    details.TextSize = 11
    details.Font = Enum.Font.Gotham
    details.TextWrapped = true
    details.TextXAlignment = Enum.TextXAlignment.Left
    details.TextYAlignment = Enum.TextYAlignment.Top
    details.Text = "Automatic block pose is hidden locally; your manual F/G actions are preserved. " ..
        "Other players may still see replicated animations; the server controls blocking."
    details.Parent = card

    local enabled, alive, keyDown = false, true, false
    -- More of each cycle is spent in F-down. The game may require a held guard,
    -- a tap/parry, or have cooldowns; faster pulses cannot force server defense.
    local TAP_DOWN_TIME = 0.085
    local TAP_UP_TIME = 0.050
    local tapActive = false
    local nextTapAction = math.huge
    local POSE_CHECK_INTERVAL = 0.016 -- at most one check per rendered simulation frame
    local rateStarted = os.clock()
    local tapsThisWindow = 0
    local manualFDown = false
    local manualGDown = false
    local lastPunchInput = -math.huge
    local PUNCH_GRACE_SECONDS = 0.35 -- don't stomp real punches with F taps
    local hiddenPoseRefresh = 0
    local syntheticPoseUntil = -math.huge
    local manualPoseUntil = -math.huge
    local AUTO_POSE_WINDOW = 0.22
    local manualInheritedSynthetic = false
    local hiddenTrackCount = 0
    local syntheticDispatch = false
    -- Match the input echoes from our own F taps, without ignoring genuine manual F.
    local expectedSyntheticF = {}
    local manualPauseUntil = -math.huge
    local lastManualRelease = -math.huge
    local MANUAL_F_GRACE = 0.42
    local MANUAL_G_GRACE = 0.55
    local function queueSyntheticF(isDown)
        expectedSyntheticF[#expectedSyntheticF + 1] = {
            down = isDown,
            at = os.clock(),
        }
        -- A bounded queue avoids stale entries when the executor emits no input echo.
        while #expectedSyntheticF > 12 do table.remove(expectedSyntheticF, 1) end
    end
    local function isSyntheticFEvent(isDown)
        local now = os.clock()
        -- Prefer physical F input: only a synchronous or very recent echo is synthetic.
        -- A wider window could silently swallow actual F presses while spamming.
        local ECHO_WINDOW = 0.048 -- allows one/two-frame synthetic echoes
        for i = #expectedSyntheticF, 1, -1 do
            if now - expectedSyntheticF[i].at > ECHO_WINDOW then
                table.remove(expectedSyntheticF, i)
            end
        end
        for i, item in ipairs(expectedSyntheticF) do
            if item.down == isDown then
                table.remove(expectedSyntheticF, i)
                return true
            end
        end
        return syntheticDispatch
    end
    local function pauseAutoFor(seconds)
        manualPauseUntil = math.max(manualPauseUntil, os.clock() + seconds)
    end
    local tapRevision = 0
    local keyOwnerRevision = nil -- old worker cannot release a newer worker's F
    local generation = 0
    local blockBackend = nil
    local characterConnections = {}
    local note = "OFF. Normal game controls."
    local BLOCK_ANIMATION_ID = "125498359087624"
    local suppressedTracks = setmetatable({}, {__mode = "k"})
    local activeAnimator = nil

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "AUTO BLOCK: ON" or "AUTO BLOCK: OFF"
        animateToggle(toggle, enabled)
        status.Text = note
    end

    local function sendF(isDown)
        -- Mark the visual window BEFORE dispatch; AnimationPlayed can run
        -- synchronously from this input call. Releases do not extend it.
        if isDown then
            syntheticPoseUntil = os.clock() + AUTO_POSE_WINDOW
        end
        syntheticDispatch = true
        queueSyntheticF(isDown)
        local ok, err = false, nil
        if blockBackend == "legacy" and type(keypress) == "function"
            and type(keyrelease) == "function" then
            ok, err = pcall(isDown and keypress or keyrelease, 0x46)
        else
            ok, err = pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(isDown, Enum.KeyCode.F, false, game)
            end)
            if ok then blockBackend = "vim" end
            if not ok and blockBackend ~= "vim" and type(keypress) == "function"
                and type(keyrelease) == "function" then
                ok, err = pcall(isDown and keypress or keyrelease, 0x46)
                if ok then blockBackend = "legacy" end
            end
        end
        syntheticDispatch = false
        return ok, err
    end

    local function releaseF(force, ownerRevision)
        if ownerRevision ~= nil and keyOwnerRevision ~= ownerRevision then return end
        if not keyDown then return end
        -- Ordinary release avoids cancelling a real held F. A forced release is
        -- mandatory when the auto-tap worker stops, unloads or changes character;
        -- otherwise synthetic F could be left pressed indefinitely.
        if manualFDown and not force then return end
        keyDown = false
        keyOwnerRevision = nil
        local ok, err = sendF(false)
        if not ok then warn("[VOID HUB Auto Block] Could not release F: " .. tostring(err)) end
    end

    local function restoreBlockPose(restoreForManualF)
        -- Do not re-show an automatic block pose when G or M1 interrupts
        -- it. On a genuine manual F press, allow normal block animation.
        for track in pairs(suppressedTracks) do
            if restoreForManualF then
                pcall(function()
                    if track.IsPlaying then track:AdjustWeight(1, 0) end
                end)
            end
            suppressedTracks[track] = nil
        end
    end

    local function disconnectCharacter()
        restoreBlockPose()
        for _, conn in ipairs(characterConnections) do
            conn:Disconnect()
        end
        table.clear(characterConnections)
        activeAnimator = nil
    end

    local function trackInfo(track)
        local name, id = "", ""
        pcall(function()
            local anim = track.Animation
            if anim then
                name = tostring(anim.Name):lower()
                id = tostring(anim.AnimationId)
            end
        end)
        return name, id
    end

    local function isExactBlockAnimation(track)
        local name, id = trackInfo(track)
        if id:match("(%d+)$") == BLOCK_ANIMATION_ID then return true end
        -- Optional fallback for game versions where the same block pose
        -- receives a different asset ID but an identifiable track name.
        local trackName = ""
        pcall(function() trackName = tostring(track.Name):lower() end)
        local combined = name .. " " .. trackName
        return combined:find("block", 1, true) ~= nil
            or combined:find("guard", 1, true) ~= nil
    end

    local function isPunching()
        if os.clock() - lastPunchInput < PUNCH_GRACE_SECONDS then return true end
        local ok, held = pcall(function()
            return UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
        end)
        return ok and held or false
    end

    local function shouldHideBlockPose()
        local now = os.clock()
        -- Do not require not isPunching() or manualPauseUntil here:
        -- they previously let the automatic block pose visibly pop back
        -- up during combat even when it was started by the synthetic F.
        return alive and enabled and activeAnimator ~= nil
            and now <= syntheticPoseUntil and now > manualPoseUntil
            and not manualFDown and not manualGDown
            and not UIS:IsKeyDown(Enum.KeyCode.G)
            and not UIS:GetFocusedTextBox()
    end

    local function fadeBlockPose(track)
        -- Visual-only: do not Stop() the animation, which could interfere with combat.
        local function fade()
            if shouldHideBlockPose() and isExactBlockAnimation(track) then
                pcall(function()
                    if not suppressedTracks[track] then
                        hiddenTrackCount += 1
                    end
                    suppressedTracks[track] = true
                    track:AdjustWeight(0, 0)
                end)
            end
        end
        fade()
        task.defer(fade)
        task.delay(0.016, fade)
        task.delay(0.03, fade)
        task.delay(0.09, fade)
    end

    local function considerAnimation(track)
        -- No generic Action-track learning: that could accidentally hide G or punches.
        if isExactBlockAnimation(track) and shouldHideBlockPose() then
            fadeBlockPose(track)
        end
    end

    local function pressF(ownerRevision)
        if not alive or not enabled or keyDown or manualFDown or manualGDown
            or os.clock() < manualPauseUntil
            or UIS:IsKeyDown(Enum.KeyCode.G) or isPunching() then
            return false, "paused"
        end
        local character = Player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid or humanoid.Health <= 0 then
            note = "ON. Waiting for respawn."
            render()
            return false, "paused"
        end
        if UIS:GetFocusedTextBox() then
            note = "ON. Paused while typing."
            render()
            return false, "paused"
        end

        keyDown = true -- arm animation listener before synchronous input callback
        keyOwnerRevision = ownerRevision
        local ok, err = sendF(true)
        if ok then
            -- Do not queue delayed jobs on every rapid pulse.
            -- Successful synthetic down; the loop counts a completed pulse on key-up.
        else
            keyDown = false
            keyOwnerRevision = nil
            note = "ON, but simulated F input failed (executor restriction)."
            warn("[VOID HUB Auto Block] F key simulation failed: " .. tostring(err))
        end
        if not ok then render() end
        return ok, ok and "sent" or "error"
    end

    local function startTapLoop()
        -- The one Heartbeat handler below advances the state machine. No per-tap
        -- task.spawn/task.wait workers: eliminates accumulated scheduling jitter.
        tapRevision += 1
        tapActive = true
        nextTapAction = os.clock()
    end

    local function attachCharacter(character)
        generation += 1
        tapRevision += 1
        tapActive = false
        nextTapAction = math.huge
        local thisGeneration = generation
        releaseF(true)
        manualFDown, manualGDown = false, false
        manualInheritedSynthetic = false
        syntheticPoseUntil, manualPoseUntil = -math.huge, -math.huge
        disconnectCharacter()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 10)
        if not alive or not enabled or thisGeneration ~= generation
            or character ~= Player.Character or not humanoid then return end
        local animator = humanoid:FindFirstChildOfClass("Animator")
            or humanoid:WaitForChild("Animator", 5)
        if animator and alive and enabled and thisGeneration == generation then
            activeAnimator = animator
            table.insert(characterConnections, animator.AnimationPlayed:Connect(function(track)
                considerAnimation(track)
            end))
        end
        table.insert(characterConnections, humanoid.Died:Connect(function()
            if not alive or thisGeneration ~= generation then return end
            releaseF(true)
            note = "ON. Waiting for respawn; F will be requested again."
            render()
        end))
        task.delay(0.35, function()
            if alive and enabled and thisGeneration == generation
                and Player.Character == character then
                startTapLoop()
            end
        end)
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        generation += 1
        tapRevision += 1
        tapActive = false
        nextTapAction = math.huge
        releaseF(true)
        if not enabled then
            manualFDown, manualGDown = false, false
            syntheticPoseUntil, manualPoseUntil = -math.huge, -math.huge
            table.clear(expectedSyntheticF)
        end
        disconnectCharacter()
        if enabled then
            rateStarted = os.clock()
            tapsThisWindow = 0
            note = "ON. Measuring fast F input taps..."
            if Player.Character then task.spawn(attachCharacter, Player.Character) end
        else
            note = "OFF. Synthetic F released; normal controls available."
        end
        render()
    end)

    bindGlobal(Player.CharacterAdded, function(character)
        if enabled then task.spawn(attachCharacter, character) end
    end)
    bindGlobal(UIS.TextBoxFocused, function()
        if not enabled then return end
        releaseF(true)
        restoreBlockPose()
        note = "ON. Paused while typing."
        render()
    end)
    -- Regular punches, F and G take priority over synthetic F key events.
    -- Never consume the user's input or require a nearby opponent.
    bindGlobal(UIS.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            lastPunchInput = os.clock()
            pauseAutoFor(PUNCH_GRACE_SECONDS)
            releaseF()
            restoreBlockPose()
        elseif input.KeyCode == Enum.KeyCode.G then
            manualGDown = true
            manualPoseUntil = os.clock() + MANUAL_G_GRACE
            syntheticPoseUntil = -math.huge
            pauseAutoFor(MANUAL_G_GRACE)
            -- Only release an automatic F. Never interfere with held manual F.
            if not manualFDown then releaseF(true) end
            restoreBlockPose()
        elseif input.KeyCode == Enum.KeyCode.F then
            if isSyntheticFEvent(true) then return end
            -- A physical F can begin during an automatic F-down. Transfer
            -- that virtual hold to the physical key, so a late virtual F-up
            -- cannot cancel a normal manual block.
            syntheticPoseUntil = -math.huge
            manualPoseUntil = os.clock() + MANUAL_F_GRACE
            if keyDown then
                keyDown = false
                keyOwnerRevision = nil
                manualInheritedSynthetic = true
            end
            manualFDown = true
            pauseAutoFor(MANUAL_F_GRACE)
            restoreBlockPose(true)
        end
    end)
    bindGlobal(UIS.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            lastPunchInput = os.clock()
            pauseAutoFor(PUNCH_GRACE_SECONDS)
        elseif input.KeyCode == Enum.KeyCode.G then
            manualGDown = false
            manualPoseUntil = math.max(manualPoseUntil, os.clock() + MANUAL_G_GRACE)
            pauseAutoFor(MANUAL_G_GRACE)
        elseif input.KeyCode == Enum.KeyCode.F then
            if isSyntheticFEvent(false) then return end
            if manualFDown then
                manualFDown = false
                lastManualRelease = os.clock()
                manualPoseUntil = lastManualRelease + MANUAL_F_GRACE
                pauseAutoFor(MANUAL_F_GRACE)
                if manualInheritedSynthetic then
                    -- The real key is up; it is now safe to release the
                    -- virtual F that we transferred to this manual hold.
                    manualInheritedSynthetic = false
                    sendF(false)
                end
                releaseF()
            end
        end
    end)
    -- All synthetic key transitions are scheduled on ONE Heartbeat connection.
    -- This respects frame rate, avoids task.wait jitter, and yields immediately
    -- to manual F/G, mouse punches, chat focus, death or GUI shutdown.
    bindGlobal(RunService.Heartbeat, function(dt)
        if not alive or not enabled or not Gui.Parent then return end
        local now = os.clock()

        if tapActive then
            local character = Player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local canTap = humanoid and humanoid.Health > 0
                and not UIS:GetFocusedTextBox() and not manualFDown and not manualGDown
                and not UIS:IsKeyDown(Enum.KeyCode.G) and not isPunching()
                and now >= manualPauseUntil
                and now - lastManualRelease >= MANUAL_F_GRACE

            if not canTap then
                releaseF(false)
                -- Restart only once after a pause, rather than catching up missed
                -- taps in a burst. A real held F is never force-released here.
                nextTapAction = now
                if manualFDown or manualGDown or isPunching() then
                    restoreBlockPose()
                end
            elseif now >= nextTapAction then
                if keyDown then
                    releaseF(false)
                    if not keyDown then
                        tapsThisWindow += 1
                        nextTapAction = now + TAP_UP_TIME
                    else
                        -- If a real F is held concurrently, wait rather than
                        -- repeatedly trying to release an owned key.
                        nextTapAction = now + 0.025
                    end
                else
                    local ok, reason = pressF(tapRevision)
                    if ok then
                        nextTapAction = now + TAP_DOWN_TIME
                    elseif reason == "error" then
                        enabled = false
                        tapActive = false
                        releaseF(true)
                        restoreBlockPose()
                        note = "OFF. F input unavailable in this environment."
                        render()
                        return
                    else
                        nextTapAction = now + 0.025
                    end
                end
            end

            local elapsed = now - rateStarted
            if elapsed >= 1 then
                local inputRate = math.floor(tapsThisWindow / elapsed * 10 + 0.5) / 10
                note = ("ON. F guard %.1f/sec | auto pose matched: %d | manual F/G priority")
                    :format(inputRate, hiddenTrackCount)
                render()
                rateStarted = now
                tapsThisWindow = 0
            end
        end

        -- Only the observed F-linked block animation is visually faded;
        -- leave every other combat animation and the real F/G animations alone.
        if not activeAnimator then return end
        hiddenPoseRefresh += dt
        if hiddenPoseRefresh < POSE_CHECK_INTERVAL then return end
        hiddenPoseRefresh = 0
        if not shouldHideBlockPose() then
            restoreBlockPose()
            return
        end
        pcall(function()
            for _, track in ipairs(activeAnimator:GetPlayingAnimationTracks()) do
                if isExactBlockAnimation(track) then
                    suppressedTracks[track] = true
                    if track.WeightTarget > 0.005 or track.WeightCurrent > 0.005 then
                        track:AdjustWeight(0, 0)
                    end
                end
            end
        end)
    end)
    -- Render-frame fade adds a final local pass after the animation driver.
    -- No animation is stopped here, which avoids breaking game combat logic.
    bindGlobal(RunService.RenderStepped, function()
        if not shouldHideBlockPose() then return end
        pcall(function()
            for _, track in ipairs(activeAnimator:GetPlayingAnimationTracks()) do
                if isExactBlockAnimation(track) then
                    if not suppressedTracks[track] then hiddenTrackCount += 1 end
                    suppressedTracks[track] = true
                    track:AdjustWeight(0, 0)
                end
            end
        end)
    end)

    -- Resumes after physical input releases and text entry; no extra controls.
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        generation += 1
        tapRevision += 1
        tapActive = false
        nextTapAction = math.huge
        releaseF(true)
        if manualInheritedSynthetic then
            manualInheritedSynthetic = false
            sendF(false)
        end
        syntheticPoseUntil, manualPoseUntil = -math.huge, -math.huge
        disconnectCharacter()
    end)
    render()
end

-- Duplicate Defense Autodecline panel removed in V56.
-- Imported Autodecline under the Whitelists tab remains unchanged.

-- Verify that every requested tool is on the Defense tab.
do
    local needed = {
        "DefenseAntiGrab", "DefenseAntiRagdoll",
        "DefenseAntiVoid"
    }
    local found = 0
    for _, name in ipairs(needed) do
        local card = DefensePage:FindFirstChild(name)
        if card and card:IsA("GuiObject") then
            card.Visible = true
            found += 1
        else
            warn("[VOID HUB V9] Missing Defense card: " .. name)
        end
    end
    print("[VOID HUB V56] Defense tab: " .. found .. "/3 cards loaded")
end

-- =====================================================================
-- Orbital Player coordination: other movement tools pause when active.
local MovementOrbitActive = false

-- TP WALK â ground + air movement boost without locking character yaw.
-- Movement direction comes from the player's Humanoid, not camera input.
-- Doesn't edit WalkSpeed, Grab or Anti-Void modules.
-- =====================================================================
do
    local page = pages["Movement"]
    local card = makeFeatureCard(page, "TP Walk", 0)
    card.Size = UDim2.fromOffset(520, 238)

    local enabled = false
    local extraSpeed = 120 -- additional studs/second above normal walking (120â500)
    local alive = true

    local toggle = Instance.new("TextButton")
    toggle.Name = "TPWalkToggle"
    toggle.Position = UDim2.fromOffset(16, 44)
    toggle.Size = UDim2.fromOffset(190, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local speedTitle = Instance.new("TextLabel")
    speedTitle.Position = UDim2.fromOffset(225, 44)
    speedTitle.Size = UDim2.fromOffset(118, 34)
    speedTitle.BackgroundTransparency = 1
    speedTitle.Text = "Extra speed:"
    speedTitle.TextColor3 = Color3.fromRGB(40, 42, 55)
    speedTitle.Font = Enum.Font.GothamBold
    speedTitle.TextSize = 12
    speedTitle.Parent = card

    local speedBox = Instance.new("TextBox")
    speedBox.Name = "TPWalkSpeed"
    speedBox.Position = UDim2.fromOffset(345, 44)
    speedBox.Size = UDim2.fromOffset(60, 36)
    speedBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    speedBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    speedBox.Font = Enum.Font.GothamBold
    speedBox.TextSize = 12
    speedBox.Text = tostring(extraSpeed)
    speedBox.ClearTextOnFocus = false
    speedBox.Parent = card
    corner(speedBox, 8)

    local apply = Instance.new("TextButton")
    apply.Name = "TPWalkApply"
    apply.Position = UDim2.fromOffset(415, 44)
    apply.Size = UDim2.fromOffset(90, 36)
    apply.Font = Enum.Font.GothamBold
    apply.TextSize = 12
    apply.Text = "APPLY"
    apply.AutoButtonColor = false
    apply.Parent = card
    corner(apply, 8)
    animateToggle(apply, false)

    local info = Instance.new("TextLabel")
    info.Position = UDim2.fromOffset(16, 101)
    info.Size = UDim2.fromOffset(489, 119)
    info.BackgroundTransparency = 1
    info.TextColor3 = Color3.fromRGB(40, 42, 55)
    info.Font = Enum.Font.Gotham
    info.TextSize = 12
    info.TextWrapped = true
    info.TextXAlignment = Enum.TextXAlignment.Left
    info.TextYAlignment = Enum.TextYAlignment.Top
    info.Parent = card

    local function render(note)
        toggle.Text = enabled and "TP WALK: ON" or "TP WALK: OFF"
        animateToggle(toggle, enabled)
        info.Text = "Adds " .. extraSpeed .. " studs/sec on the ground and while jumping. " ..
            "Press WASD / move normally; stops when you stop moving.\n" ..
            "Doesn't modify normal WalkSpeed. Server movement rules may override it." ..
            (note and ("\n" .. note) or "")
    end

    local function setSpeed()
        local value = tonumber(speedBox.Text)
        if not value then
            speedBox.Text = tostring(extraSpeed)
            render("Enter a number from 120 to 500.")
            return
        end
        extraSpeed = math.clamp(math.floor(value + 0.5), 120, 500)
        speedBox.Text = tostring(extraSpeed)
        render("Speed applied.")
        print("[VOID HUB TP WALK] Extra speed:", extraSpeed)
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        render()
        print("[VOID HUB TP WALK] " .. (enabled and "ON" or "OFF"))
    end)
    apply.Activated:Connect(setSpeed)
    speedBox.FocusLost:Connect(setSpeed)
    savedApply[#savedApply + 1] = setSpeed

    -- Heartbeat runs after physics. Short delta-based moves avoid frame-rate
    -- dependent teleport jumps; character checks avoid ragdoll/grab conflicts.
    bindGlobal(RunService.Heartbeat, function(dt)
        if not alive or not enabled or not Gui.Parent or MovementOrbitActive then return end
        local character = Player.Character
        if not character then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root or humanoid.Health <= 0 or root.Anchored then return end
        if humanoid.PlatformStand or humanoid.Sit then return end
        -- Allow the boost during Jumping and Freefall too. Preserve normal
        -- gravity/jump velocity by applying only horizontal movement below.
        local direction = humanoid.MoveDirection
        local horizontal = Vector3.new(direction.X, 0, direction.Z)
        if horizontal.Magnitude < 0.05 then return end
        local step = horizontal.Unit * (extraSpeed * math.min(math.max(dt, 0), 0.06))
        if step.Magnitude <= 0 then return end
        -- Move the root in the current direction without repeatedly pivoting
        -- the entire rig. The current CFrame rotation (yaw) stays unchanged,
        -- so Humanoid.AutoRotate and the game's camera/turn controls can work.
        -- This is still a client-side request; game-zone rules may override it.
        root.CFrame = root.CFrame + step
    end)

    Gui.Destroying:Connect(function()
        alive = false
        enabled = false
    end)
    render()
end

-- =====================================================================
local syncNoSlowSpeedBaseline = nil -- optional coordination with Movement Walk Speed

-- MOVEMENT: NO SLOW (V68)
-- Restore normal Humanoid.WalkSpeed when a hit/slow reduces it.
-- Event-driven: no Heartbeat spam or remote calls. Respawn persistent.
-- This only affects local WalkSpeed; server-enforced movement may override.
-- TP Walk is kept separate and unchanged.
-- =====================================================================
do
    local page = pages["Movement"]
    local card = makeFeatureCard(page, "No Slow", 260)
    card.Name = "MovementNoSlow"
    card.Size = UDim2.fromOffset(520, 145)

    local toggle = Instance.new("TextButton")
    toggle.Name = "NoSlowToggle"
    toggle.Position = UDim2.fromOffset(16, 47)
    toggle.Size = UDim2.fromOffset(190, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "NoSlowStatus"
    status.Position = UDim2.fromOffset(220, 43)
    status.Size = UDim2.fromOffset(282, 46)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    status.TextWrapped = true
    status.Parent = card

    local description = Instance.new("TextLabel")
    description.Position = UDim2.fromOffset(16, 97)
    description.Size = UDim2.fromOffset(485, 39)
    description.BackgroundTransparency = 1
    description.TextColor3 = Color3.fromRGB(85, 88, 104)
    description.Font = Enum.Font.Gotham
    description.TextSize = 11
    description.TextWrapped = true
    description.TextXAlignment = Enum.TextXAlignment.Left
    description.TextYAlignment = Enum.TextYAlignment.Top
    description.Text = "Restores pre-slow walking speed on hit. Stays ON through respawn. Server movement rules may override it."
    description.Parent = card

    local alive, enabled = true, false
    local trackedHumanoid = nil
    local baselineSpeed = 16
    local corrections = 0
    local lastRestore = 0
    local pendingRetry = false
    local trackedConnections = {}
    local restoring = false

    -- Keep No Slow compatible with an intentional Walk Speed change.
    syncNoSlowSpeedBaseline = function(humanoid, desiredBaseline)
        if alive and trackedHumanoid == humanoid and type(desiredBaseline) == "number" then
            baselineSpeed = desiredBaseline
        end
    end

    local function disconnectCharacter()
        for _, connection in ipairs(trackedConnections) do
            connection:Disconnect()
        end
        table.clear(trackedConnections)
        trackedHumanoid = nil
        pendingRetry = false
    end

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "No Slow: ON" or "No Slow: OFF"
        animateToggle(toggle, enabled)
        if enabled then
            status.Text = ("Normal speed: %.1f\nSlows corrected: %d"):format(baselineSpeed, corrections)
        else
            status.Text = "OFF. Normal game movement."
        end
    end

    local restoreSpeed
    restoreSpeed = function()
        local h = trackedHumanoid
        if not alive or not enabled or not h or not h.Parent or h.Health <= 0 then return end
        -- Do not interfere with legitimate sitting/knockdown states.
        if h.Sit or h.PlatformStand then return end
        if h.WalkSpeed >= baselineSpeed - 0.01 or restoring then return end
        local now = os.clock()
        if now - lastRestore < 0.12 then
            if not pendingRetry then
                pendingRetry = true
                task.delay(0.13, function()
                    pendingRetry = false
                    if alive and h == trackedHumanoid then restoreSpeed() end
                end)
            end
            return
        end
        lastRestore = now
        restoring = true
        h.WalkSpeed = baselineSpeed
        restoring = false
        corrections += 1
        if corrections <= 2 or corrections % 5 == 0 then render() end
    end

    local function attachCharacter(character)
        disconnectCharacter()
        local h = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
        if not alive or not h or character ~= Player.Character then return end
        trackedHumanoid = h
        local original = h.WalkSpeed
        baselineSpeed = original > 0 and original or 16
        lastRestore = 0

        table.insert(trackedConnections, h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if restoring or not alive or h ~= trackedHumanoid then return end
            local current = h.WalkSpeed
            if enabled and current < baselineSpeed - 0.01 then
                restoreSpeed()
            elseif current > baselineSpeed then
                -- Track genuine increases, such as the game's own sprint speed.
                baselineSpeed = current
            elseif not enabled and current > 0 then
                baselineSpeed = current
            end
        end))
        local lastHealth = h.Health
        table.insert(trackedConnections, h.HealthChanged:Connect(function(health)
            if enabled and health < lastHealth and health > 0 then
                restoreSpeed() -- Also catches a slow applied just before damage.
                task.delay(0.10, function()
                    if alive and enabled and h == trackedHumanoid then restoreSpeed() end
                end)
            end
            lastHealth = health
        end))
        table.insert(trackedConnections, h:GetPropertyChangedSignal("Sit"):Connect(function()
            if enabled and not h.Sit then restoreSpeed() end
        end))
        if enabled then restoreSpeed() end
        render()
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        if enabled and trackedHumanoid then
            local current = trackedHumanoid.WalkSpeed
            if current > 0 then baselineSpeed = current end
            restoreSpeed()
        end
        render()
    end)

    bindGlobal(Player.CharacterAdded, function(character)
        task.spawn(attachCharacter, character)
    end)
    if Player.Character then task.spawn(attachCharacter, Player.Character) end
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        syncNoSlowSpeedBaseline = nil
        disconnectCharacter()
    end)
    render()
end

-- =====================================================================
-- MOVEMENT: WALK SPEED (V103)
-- Directly adjusts the local character Humanoid.WalkSpeed, separately from
-- TP Walk's extra CFrame displacement. No Heartbeat or remote spam.
-- Editable 16-200 studs/s, ON/OFF, remembers the ON state after respawn.
-- Client-side WalkSpeed can be overridden by server-enforced speed rules.
-- =====================================================================
do
    local page = pages["Movement"]
    local card = makeFeatureCard(page, "Walk Speed", 260)
    card.Name = "MovementWalkSpeed"
    card.Position = UDim2.fromOffset(538, 260)
    card.Size = UDim2.fromOffset(330, 174)

    local toggle = Instance.new("TextButton")
    toggle.Name = "WalkSpeedToggle"
    toggle.Position = UDim2.fromOffset(16, 48)
    toggle.Size = UDim2.fromOffset(117, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local speedBox = Instance.new("TextBox")
    speedBox.Name = "WalkSpeedInput"
    speedBox.Position = UDim2.fromOffset(144, 48)
    speedBox.Size = UDim2.fromOffset(69, 36)
    speedBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    speedBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    speedBox.Font = Enum.Font.GothamBold
    speedBox.TextSize = 13
    speedBox.Text = "32"
    speedBox.PlaceholderText = "16-200"
    speedBox.ClearTextOnFocus = false
    speedBox.Parent = card
    corner(speedBox, 8)

    local applyButton = Instance.new("TextButton")
    applyButton.Name = "WalkSpeedApply"
    applyButton.Position = UDim2.fromOffset(224, 48)
    applyButton.Size = UDim2.fromOffset(89, 36)
    applyButton.Font = Enum.Font.GothamBold
    applyButton.TextSize = 12
    applyButton.Text = "APPLY"
    applyButton.AutoButtonColor = false
    applyButton.Parent = card
    corner(applyButton, 8)
    animateToggle(applyButton, false)

    local status = Instance.new("TextLabel")
    status.Name = "WalkSpeedStatus"
    status.Position = UDim2.fromOffset(16, 97)
    status.Size = UDim2.fromOffset(297, 65)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = card

    local alive, enabled = true, false
    local selectedSpeed = 32
    local normalSpeed = nil
    local currentHumanoid = nil
    local speedChangedConnection = nil
    local writingSpeed = false
    local retryScheduled = false
    local lastWrite = -math.huge

    local function render(note)
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "WALK: ON" or "WALK: OFF"
        animateToggle(toggle, enabled)
        local message = enabled
            and ("Speed: " .. selectedSpeed .. " studs/s. Active after respawn.")
            or ("OFF. Normal WalkSpeed; set 16-200, then turn ON.")
        status.Text = message .. "\nSeparate from TP Walk." ..
            (note and ("\n" .. note) or "")
    end

    local function setHumanoidSpeed()
        local h = currentHumanoid
        if not alive or not enabled or not h or h.Parent == nil then return end
        if h.Health <= 0 or h.Sit or h.PlatformStand then return end
        if writingSpeed or math.abs(h.WalkSpeed - selectedSpeed) < 0.01 then return end
        local now = os.clock()
        if now - lastWrite < 0.09 then
            if not retryScheduled then
                retryScheduled = true
                task.delay(0.10, function()
                    retryScheduled = false
                    if alive and enabled and currentHumanoid == h then
                        setHumanoidSpeed()
                    end
                end)
            end
            return
        end
        lastWrite = now
        writingSpeed = true
        h.WalkSpeed = selectedSpeed
        writingSpeed = false
    end

    local function attachCharacter(character)
        if speedChangedConnection then
            speedChangedConnection:Disconnect()
            speedChangedConnection = nil
        end
        currentHumanoid = nil
        local h = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
        if not alive or not h or Player.Character ~= character then return end
        currentHumanoid = h
        normalSpeed = h.WalkSpeed
        lastWrite = -math.huge
        speedChangedConnection = h:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
            if alive and enabled and currentHumanoid == h and not writingSpeed then
                setHumanoidSpeed()
            end
        end)
        if enabled then
            if syncNoSlowSpeedBaseline then syncNoSlowSpeedBaseline(h, selectedSpeed) end
            setHumanoidSpeed()
        end
        render()
    end

    local function applyInput()
        local value = tonumber(speedBox.Text)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            speedBox.Text = tostring(selectedSpeed)
            render("Enter a valid number from 16 to 200.")
            return
        end
        selectedSpeed = math.clamp(math.floor(value + 0.5), 16, 200)
        speedBox.Text = tostring(selectedSpeed)
        if enabled then
            if syncNoSlowSpeedBaseline and currentHumanoid then
                syncNoSlowSpeedBaseline(currentHumanoid, selectedSpeed)
            end
            lastWrite = -math.huge
            setHumanoidSpeed()
        end
        render("Speed updated.")
    end

    persistentToggle(toggle, function()
        if enabled then
            enabled = false
            local h = currentHumanoid
            if h and h.Parent and normalSpeed then
                if syncNoSlowSpeedBaseline then syncNoSlowSpeedBaseline(h, normalSpeed) end
                writingSpeed = true
                h.WalkSpeed = normalSpeed
                writingSpeed = false
            end
            render("Original walking speed restored.")
        else
            local h = currentHumanoid
            if h and h.Parent then normalSpeed = h.WalkSpeed end
            enabled = true
            if syncNoSlowSpeedBaseline and h then syncNoSlowSpeedBaseline(h, selectedSpeed) end
            lastWrite = -math.huge
            setHumanoidSpeed()
            render()
        end
    end)
    applyButton.Activated:Connect(applyInput)
    speedBox.FocusLost:Connect(applyInput)

    bindGlobal(Player.CharacterAdded, function(character)
        task.spawn(attachCharacter, character)
    end)
    if Player.Character then task.spawn(attachCharacter, Player.Character) end
    Gui.Destroying:Connect(function()
        local h = currentHumanoid
        if enabled and h and h.Parent and normalSpeed then
            if syncNoSlowSpeedBaseline then syncNoSlowSpeedBaseline(h, normalSpeed) end
            h.WalkSpeed = normalSpeed
        end
        alive, enabled = false, false
        if speedChangedConnection then speedChangedConnection:Disconnect() end
        speedChangedConnection = nil
        currentHumanoid = nil
    end)
    render()
end

-- =====================================================================
-- MOVEMENT: FOLLOW (V63) - FAST + RESPAWN-PERSISTENT
-- Keep Follow ON until the user switches it OFF or the hub is unloaded.
-- Moves the LOCAL player behind the target (+local Z), not the target.
-- Resumes after either character respawns; never runs while own HP = 0.
-- =====================================================================
do
    local page = pages["Movement"]
    local card = makeFeatureCard(page, "Follow  |  4 studs behind", 0)
    card.Name = "MovementFollow"
    card.Position = UDim2.fromOffset(538, 0)
    card.Size = UDim2.fromOffset(330, 238)

    local nameBox = Instance.new("TextBox")
    nameBox.Name = "FollowTargetInput"
    nameBox.Position = UDim2.fromOffset(16, 49)
    nameBox.Size = UDim2.fromOffset(172, 36)
    nameBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    nameBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    nameBox.PlaceholderText = "Username / display name"
    nameBox.PlaceholderColor3 = Color3.fromRGB(115, 120, 135)
    nameBox.Font = Enum.Font.Gotham
    nameBox.TextSize = 12
    nameBox.Text = ""
    nameBox.ClearTextOnFocus = false
    nameBox.Parent = card
    corner(nameBox, 8)

    local toggle = Instance.new("TextButton")
    toggle.Name = "FollowToggle"
    toggle.Position = UDim2.fromOffset(196, 49)
    toggle.Size = UDim2.fromOffset(118, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "FollowStatus"
    status.Position = UDim2.fromOffset(16, 101)
    status.Size = UDim2.fromOffset(296, 110)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(40, 42, 55)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = card

    local enabled = false
    local alive = true
    local target = nil
    local targetUserId = nil
    local targetLabel = ""
    local elapsed = 0
    local note = "Enter a unique username, display name, or part of either."
    local UPDATE_INTERVAL = 0.05 -- 20 Hz (3x faster than V62); avoid full-frame spam.
    local BEHIND_STUDS = 4
    local MOVE_EPSILON = 0.3

    local function render()
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "FOLLOW: ON" or "FOLLOW: OFF"
        animateToggle(toggle, enabled)
        status.Text = note .. "\n4 studs behind | auto-resumes after respawn."
    end

    local function setNote(nextNote)
        if note ~= nextNote then
            note = nextNote
            render()
        end
    end

    local function stopFollow()
        enabled = false
        target = nil
        targetUserId = nil
        targetLabel = ""
        elapsed = 0
        setNote("Follow OFF.")
        render()
    end

    local function getTarget()
        if not targetUserId then return nil end
        if target and target.Parent == Players and target.UserId == targetUserId then
            return target
        end
        target = Players:GetPlayerByUserId(targetUserId)
        return target
    end

    local function updateFollow()
        if not enabled or not alive or not Gui.Parent or MovementOrbitActive then return end
        local followedPlayer = getTarget()
        if not followedPlayer then
            setNote("Waiting for " .. targetLabel .. " to join...")
            return
        end

        local ownCharacter = Player.Character
        local otherCharacter = followedPlayer.Character
        if not ownCharacter or not otherCharacter then
            setNote("Waiting for a character to spawn...")
            return
        end

        local ownHumanoid = ownCharacter:FindFirstChildOfClass("Humanoid")
        local otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
        local ownRoot = ownCharacter:FindFirstChild("HumanoidRootPart")
        local otherRoot = otherCharacter:FindFirstChild("HumanoidRootPart")
        if not ownHumanoid or not ownRoot or not otherHumanoid or not otherRoot then
            setNote("Waiting for character parts...")
            return
        end

        if ownHumanoid.Health <= 0 then
            -- Important: death is NOT an OFF signal. Resume after CharacterAdded.
            setNote("Waiting for your respawn; Follow is still ON.")
            return
        end
        if otherHumanoid.Health <= 0 then
            setNote("Waiting for " .. targetLabel .. " to respawn...")
            return
        end
        if ownRoot.Anchored or ownHumanoid.PlatformStand or DeathTPIsEscaping then
            -- Transient character state; do not disconnect or toggle off.
            return
        end

        -- Roblox characters face local -Z. Local +Z is directly behind.
        local destinationPoint = (otherRoot.CFrame * CFrame.new(0, 0, BEHIND_STUDS)).Position
        if (ownRoot.Position - destinationPoint).Magnitude < MOVE_EPSILON then
            setNote("Following " .. targetLabel .. " | 4 studs behind.")
            return
        end
        local levelFacing = Vector3.new(otherRoot.Position.X, destinationPoint.Y, otherRoot.Position.Z)
        local destination = CFrame.lookAt(destinationPoint, levelFacing)
        local ok, err = pcall(function()
            if ownCharacter == Player.Character and ownRoot.Parent then
                ownCharacter:PivotTo(destination)
            end
        end)
        if ok then
            setNote("Following " .. targetLabel .. " | 4 studs behind.")
        else
            -- Errors should not silently turn Follow off. Can retry after respawn.
            setNote("Follow waiting: " .. tostring(err))
        end
    end

    persistentToggle(toggle, function()
        if enabled then
            stopFollow() -- ONLY user OFF (or hub unload) disables Follow.
            return
        end
        local query = nameBox.Text:match("^%s*(.-)%s*$"):gsub("^@", "")
        if query == "" then
            setNote("Enter a player name first.")
            return
        end
        local found, ambiguous = resolveUniqueListedName(query)
        if not found then
            setNote(ambiguous and "Several players match. Enter more letters."
                or "No online player matches that name.")
            return
        end
        target = found
        targetUserId = found.UserId
        targetLabel = found.Name
        enabled = true
        elapsed = 0
        render()
        updateFollow() -- Instant first move, then 20 Hz.
    end)

    bindGlobal(RunService.Heartbeat, function(dt)
        if not enabled or not alive then return end
        elapsed += math.min(math.max(dt, 0), 0.1)
        if elapsed < UPDATE_INTERVAL then return end
        elapsed = 0
        updateFollow()
    end)

    bindGlobal(Player.CharacterRemoving, function()
        if enabled then setNote("Waiting for your respawn; Follow is still ON.") end
    end)
    bindGlobal(Player.CharacterAdded, function()
        if enabled then
            elapsed = UPDATE_INTERVAL -- Next Heartbeat resumes immediately once alive.
            setNote("Respawn detected. Resuming Follow...")
        end
    end)
    bindGlobal(Players.PlayerRemoving, function(leaving)
        if enabled and leaving.UserId == targetUserId then
            target = nil
            setNote("Waiting for " .. targetLabel .. " to rejoin. Follow is ON.")
        end
    end)
    bindGlobal(Players.PlayerAdded, function(joining)
        if enabled and joining.UserId == targetUserId then
            target = joining
            elapsed = UPDATE_INTERVAL
            setNote("Player rejoined. Resuming Follow...")
        end
    end)

    Gui.Destroying:Connect(function()
        alive = false
        enabled = false
        target = nil
        targetUserId = nil
    end)
    render()
end

-- =====================================================================

-- =====================================================================
-- MOVEMENT: ORBITAL PLAYER
-- Circle the selected player with adjustable radius. Moves only the local character.
-- Heartbeat with dt-based angle and gentle lerp; Follow and TP Walk pause while ON.
-- Manual F / G / punches are untouched. Server movement rules may override movement.
-- =====================================================================
do
    local page = pages["Movement"]
    local card = makeFeatureCard(page, "Orbital Player", 0)
    card.Name = "MovementOrbitalPlayer"
    card.Size = UDim2.fromOffset(880, 192)
    card:FindFirstChildOfClass("TextLabel").Size = UDim2.fromOffset(820, 24)

    local nameBox = Instance.new("TextBox")
    nameBox.Name = "OrbitTargetInput"
    nameBox.Position = UDim2.fromOffset(16, 56)
    nameBox.Size = UDim2.fromOffset(330, 36)
    nameBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    nameBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    nameBox.Font = Enum.Font.Gotham
    nameBox.TextSize = 13
    nameBox.Text = ""
    nameBox.PlaceholderText = "Type username / display name"
    nameBox.ClearTextOnFocus = false
    nameBox.Parent = card
    corner(nameBox, 8)

    local studsLabel = Instance.new("TextLabel")
    studsLabel.Name = "StudsLabel"
    studsLabel.Position = UDim2.fromOffset(363, 55)
    studsLabel.Size = UDim2.fromOffset(56, 36)
    studsLabel.BackgroundTransparency = 1
    studsLabel.Font = Enum.Font.GothamBold
    studsLabel.TextSize = 12
    studsLabel.TextColor3 = Color3.fromRGB(40, 42, 55)
    studsLabel.Text = "Studs:"
    studsLabel.Parent = card

    local studsBox = Instance.new("TextBox")
    studsBox.Name = "OrbitStudsInput"
    studsBox.Position = UDim2.fromOffset(425, 56)
    studsBox.Size = UDim2.fromOffset(73, 36)
    studsBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    studsBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    studsBox.Font = Enum.Font.GothamBold
    studsBox.TextSize = 13
    studsBox.Text = "8"
    studsBox.PlaceholderText = "3-100"
    studsBox.ClearTextOnFocus = false
    studsBox.Parent = card
    corner(studsBox, 8)

    local applyButton = Instance.new("TextButton")
    applyButton.Name = "OrbitApplyStuds"
    applyButton.Position = UDim2.fromOffset(508, 56)
    applyButton.Size = UDim2.fromOffset(102, 36)
    applyButton.Font = Enum.Font.GothamBold
    applyButton.TextSize = 12
    applyButton.Text = "APPLY"
    applyButton.AutoButtonColor = false
    applyButton.Parent = card
    corner(applyButton, 8)
    animateToggle(applyButton, false)

    local toggle = Instance.new("TextButton")
    toggle.Name = "OrbitToggle"
    toggle.Position = UDim2.fromOffset(625, 56)
    toggle.Size = UDim2.fromOffset(237, 36)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    toggle.Parent = card
    corner(toggle, 8)

    local status = Instance.new("TextLabel")
    status.Name = "OrbitStatus"
    status.Position = UDim2.fromOffset(16, 103)
    status.Size = UDim2.fromOffset(846, 73)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextColor3 = Color3.fromRGB(52, 58, 72)
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.Parent = card

    local enabled = false
    local alive = true
    local radius = 8
    local angle = 0
    local rotationSpeed = math.rad(90) -- one orbit approximately every four seconds
    local targetId = nil
    local targetName = ""
    local trackedHumanoid = nil
    local previousAutoRotate = nil
    local lastStatusAt = 0
    local note = "Enter a player, choose 3-100 studs, then turn ON. Your character orbits the target."

    local function showStatus(nextNote)
        if nextNote then note = nextNote end
        if not alive or not Gui.Parent then return end
        toggle.Text = enabled and "ORBIT PLAYER: ON" or "ORBIT PLAYER: OFF"
        animateToggle(toggle, enabled)
        status.Text = note .. "\nRadius: " .. radius .. " studs | 90 degrees/sec | only your character moves."
    end

    local function restoreRotation()
        if trackedHumanoid and trackedHumanoid.Parent and previousAutoRotate ~= nil then
            trackedHumanoid.AutoRotate = previousAutoRotate
        end
        trackedHumanoid = nil
        previousAutoRotate = nil
    end

    local function stopOrbit(message)
        enabled = false
        MovementOrbitActive = false
        targetId = nil
        targetName = ""
        restoreRotation()
        showStatus(message or "Orbit stopped. Normal movement restored.")
    end

    local function applyStuds()
        local number = tonumber(studsBox.Text)
        if not number or number ~= number or number == math.huge or number == -math.huge then
            studsBox.Text = tostring(radius)
            showStatus("Enter a number between 3 and 100 studs.")
            return
        end
        radius = math.clamp(math.floor(number + 0.5), 3, 100)
        studsBox.Text = tostring(radius)
        showStatus(enabled and ("Orbiting " .. targetName .. ". Distance updated.")
            or "Distance saved. Enter a player and turn ON.")
    end

    applyButton.Activated:Connect(applyStuds)
    studsBox.FocusLost:Connect(function(enterPressed)
        if enterPressed or studsBox.Text ~= tostring(radius) then applyStuds() end
    end)

    persistentToggle(toggle, function()
        if enabled then
            stopOrbit()
            return
        end
        local query = (nameBox.Text or ""):match("^%s*(.-)%s*$"):gsub("^@", "")
        if query == "" then
            showStatus("Enter a player username or display name first.")
            return
        end
        local target, ambiguous = resolveUniqueListedName(query)
        if not target then
            showStatus(ambiguous and "Several players match. Use more letters or the full username."
                or "No matching player online. Check the name.")
            return
        end
        applyStuds()
        local ownChar = Player.Character
        local otherChar = target.Character
        local ownRoot = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
        local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
        if ownRoot and otherRoot then
            local delta = ownRoot.Position - otherRoot.Position
            angle = math.atan2(delta.Z, delta.X)
        else
            angle = 0
        end
        targetId = target.UserId
        targetName = target.Name
        enabled = true
        MovementOrbitActive = true
        AntiTPIntentionalTeleportUntil = os.clock() + 0.25
        showStatus("Orbiting " .. targetName .. ". Change studs anytime, or toggle OFF to stop.")
    end)

    bindGlobal(RunService.Heartbeat, function(dt)
        if not enabled or not alive or not Gui.Parent then return end
        local target = targetId and Players:GetPlayerByUserId(targetId)
        if not target then
            stopOrbit("Target left. Orbit stopped.")
            return
        end
        local ownChar = Player.Character
        local otherChar = target.Character
        local ownRoot = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
        local otherRoot = otherChar and otherChar:FindFirstChild("HumanoidRootPart")
        local ownHumanoid = ownChar and ownChar:FindFirstChildOfClass("Humanoid")
        local otherHumanoid = otherChar and otherChar:FindFirstChildOfClass("Humanoid")
        if not ownRoot or not otherRoot or not ownHumanoid or not otherHumanoid
            or ownHumanoid.Health <= 0 or otherHumanoid.Health <= 0
            or ownRoot.Anchored or ownHumanoid.Sit or ownHumanoid.PlatformStand
            or DeathTPIsEscaping then
            restoreRotation()
            if os.clock() - lastStatusAt > 1.5 then
                lastStatusAt = os.clock()
                showStatus("Waiting for you and " .. targetName .. " to be ready. Orbit stays ON.")
            end
            return
        end
        if trackedHumanoid ~= ownHumanoid then
            restoreRotation()
            trackedHumanoid = ownHumanoid
            previousAutoRotate = ownHumanoid.AutoRotate
            ownHumanoid.AutoRotate = false
        end

        local elapsed = math.clamp(tonumber(dt) or 0, 0, 0.08)
        angle = (angle + rotationSpeed * elapsed) % (math.pi * 2)
        local center = otherRoot.Position
        local targetPosition = center + Vector3.new(
            math.cos(angle) * radius, 0, math.sin(angle) * radius)
        local facing = Vector3.new(center.X, targetPosition.Y, center.Z)
        local desired = CFrame.lookAt(targetPosition, facing)
        local alpha = math.clamp(1 - math.exp(-18 * elapsed), 0.05, 0.95)
        local newCFrame = ownRoot.CFrame:Lerp(desired, alpha)
        -- Signal to the existing Anti TP tool that this is deliberate movement.
        AntiTPIntentionalTeleportUntil = os.clock() + 0.22
        ownChar:PivotTo(newCFrame)
    end)

    bindGlobal(Players.PlayerRemoving, function(leaving)
        if enabled and targetId == leaving.UserId then stopOrbit("Target left. Orbit stopped.") end
    end)
    bindGlobal(Player.CharacterAdded, function()
        if enabled then
            restoreRotation()
            showStatus("Respawned. Orbit will resume once your character is ready.")
        end
    end)
    Gui.Destroying:Connect(function()
        alive = false
        MovementOrbitActive = false
        enabled = false
        restoreRotation()
    end)
    showStatus()
end

-- MOVEMENT: SEND ANNOUNCEMENT (V128)
-- AnnouncementRequest is the client-to-server request. AnnouncementMessage
-- is server-to-client and is intentionally not fired by this client.
-- =====================================================================
do
    local page = pages["Movement"]
    page.CanvasSize = UDim2.fromOffset(0, 660)

    local card = makeFeatureCard(page, "Announcement", 454)
    card.Name = "MovementAnnouncement"
    card.Size = UDim2.fromOffset(880, 152)

    local messageBox = Instance.new("TextBox")
    messageBox.Name = "AnnouncementInput"
    messageBox.Position = UDim2.fromOffset(16, 48)
    messageBox.Size = UDim2.fromOffset(618, 38)
    messageBox.BackgroundColor3 = Color3.fromRGB(237, 239, 246)
    messageBox.TextColor3 = Color3.fromRGB(35, 38, 47)
    messageBox.Font = Enum.Font.Gotham
    messageBox.TextSize = 13
    messageBox.PlaceholderText = "Type your announcement here..."
    messageBox.Text = ""
    messageBox.ClearTextOnFocus = false
    messageBox.Parent = card
    corner(messageBox, 8)

    local sendButton = Instance.new("TextButton")
    sendButton.Name = "SendAnnouncement"
    sendButton.Position = UDim2.fromOffset(648, 48)
    sendButton.Size = UDim2.fromOffset(214, 38)
    sendButton.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
    sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    sendButton.Font = Enum.Font.GothamBold
    sendButton.TextSize = 12
    sendButton.Text = "SEND ANNOUNCEMENT"
    sendButton.Parent = card
    corner(sendButton, 8)

    local status = Instance.new("TextLabel")
    status.Name = "AnnouncementStatus"
    status.Position = UDim2.fromOffset(16, 99)
    status.Size = UDim2.fromOffset(846, 36)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(70, 74, 89)
    status.Font = Enum.Font.Gotham
    status.TextSize = 12
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Center
    status.TextWrapped = true
    status.Text = "Sends one request when clicked. The game server controls who can announce."
    status.Parent = card

    local lastRequestAt = -math.huge
    sendButton.Activated:Connect(function()
        local message = (messageBox.Text or ""):match("^%s*(.-)%s*$")
        if message == "" then
            status.Text = "Type a message first."
            return
        end
        if #message > 200 then
            status.Text = "Keep the announcement under 200 characters."
            return
        end
        if os.clock() - lastRequestAt < 2 then
            status.Text = "Please allow 2 seconds between requests."
            return
        end
        local remote = game:GetService("ReplicatedStorage"):FindFirstChild("AnnouncementRequest")
        if not (remote and remote:IsA("RemoteEvent")) then
            status.Text = "AnnouncementRequest RemoteEvent was not found."
            return
        end
        lastRequestAt = os.clock()
        local ok, err = pcall(function()
            remote:FireServer(message)
        end)
        status.Text = ok and "Request sent. Server permission and message format determine whether it appears."
            or ("Request failed: " .. tostring(err))
    end)
end

local visualPage = pages["Visual"]

local espCard = makeFeatureCard(visualPage, "ESP", 0)
local espToggle = Instance.new("TextButton")
espToggle.Size = UDim2.fromOffset(90, 32)
espToggle.Position = UDim2.fromOffset(16, 44)
espToggle.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
espToggle.Text = "OFF"
espToggle.TextColor3 = Color3.fromRGB(40, 42, 55)
espToggle.TextSize = 12
espToggle.Font = Enum.Font.GothamBold
espToggle.AutoButtonColor = false
corner(espToggle, 8)
espToggle.Parent = espCard

local espBindBtn = Instance.new("TextButton")
espBindBtn.Size = UDim2.fromOffset(140, 32)
espBindBtn.Position = UDim2.fromOffset(120, 44)
espBindBtn.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
espBindBtn.Text = "Bind: None"
espBindBtn.TextColor3 = Color3.fromRGB(40, 42, 55)
espBindBtn.TextSize = 12
espBindBtn.Font = Enum.Font.Gotham
espBindBtn.AutoButtonColor = false
corner(espBindBtn, 8)
espBindBtn.Parent = espCard

local tracersCard = makeFeatureCard(visualPage, "Tracers", 106)
local tracersToggle = Instance.new("TextButton")
tracersToggle.Size = UDim2.fromOffset(90, 32)
tracersToggle.Position = UDim2.fromOffset(16, 44)
tracersToggle.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
tracersToggle.Text = "OFF"
tracersToggle.TextColor3 = Color3.fromRGB(40, 42, 55)
tracersToggle.TextSize = 12
tracersToggle.Font = Enum.Font.GothamBold
tracersToggle.AutoButtonColor = false
corner(tracersToggle, 8)
tracersToggle.Parent = tracersCard

local tracersBindBtn = Instance.new("TextButton")
tracersBindBtn.Size = UDim2.fromOffset(140, 32)
tracersBindBtn.Position = UDim2.fromOffset(120, 44)
tracersBindBtn.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
tracersBindBtn.Text = "Bind: None"
tracersBindBtn.TextColor3 = Color3.fromRGB(40, 42, 55)
tracersBindBtn.TextSize = 12
tracersBindBtn.Font = Enum.Font.Gotham
tracersBindBtn.AutoButtonColor = false
corner(tracersBindBtn, 8)
tracersBindBtn.Parent = tracersCard

-- HEALTH BARS: client-side display of replicated player Humanoid health.
-- Reuses one BillboardGui per player; updates at 8 Hz to avoid frame lag.
do
    local card = makeFeatureCard(visualPage, "Health Bars", 0)
    card.Position = UDim2.fromOffset(450, 0)
    card.Size = UDim2.fromOffset(430, 142)

    local toggle = Instance.new("TextButton")
    toggle.Name = "HealthBarsToggle"
    toggle.Position = UDim2.fromOffset(16, 44)
    toggle.Size = UDim2.fromOffset(180, 34)
    toggle.Font = Enum.Font.GothamBold
    toggle.TextSize = 12
    toggle.AutoButtonColor = false
    corner(toggle, 8)
    toggle.Parent = card

    local detail = Instance.new("TextLabel")
    detail.BackgroundTransparency = 1
    detail.Position = UDim2.fromOffset(16, 87)
    detail.Size = UDim2.fromOffset(398, 42)
    detail.Text = "Displays names and current HP over other players."
    detail.TextWrapped = true
    detail.TextXAlignment = Enum.TextXAlignment.Left
    detail.TextColor3 = Color3.fromRGB(50, 54, 66)
    detail.TextSize = 12
    detail.Font = Enum.Font.Gotham
    detail.Parent = card

    local enabled = false
    local markers = {}

    local function removeMarker(plr)
        local record = markers[plr]
        if record then
            record.gui:Destroy()
            markers[plr] = nil
        end
    end

    local function removeAll()
        for plr in pairs(markers) do
            removeMarker(plr)
        end
    end

    local function makeMarker(plr, head)
        local bb = Instance.new("BillboardGui")
        bb.Name = "VoidHubHealthBar"
        bb.AlwaysOnTop = true
        bb.Adornee = head
        bb.Size = UDim2.fromOffset(174, 43)
        bb.StudsOffsetWorldSpace = Vector3.new(0, 3.05, 0)
        bb.Parent = Gui

        local name = Instance.new("TextLabel")
        name.Size = UDim2.fromOffset(174, 19)
        name.BackgroundTransparency = 1
        name.TextColor3 = Color3.new(1, 1, 1)
        name.TextStrokeTransparency = 0.3
        name.TextScaled = false
        name.TextSize = 12
        name.Font = Enum.Font.GothamBold
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.Parent = bb

        local track = Instance.new("Frame")
        track.Position = UDim2.fromOffset(6, 23)
        track.Size = UDim2.fromOffset(162, 11)
        track.BorderSizePixel = 0
        track.BackgroundColor3 = Color3.fromRGB(25, 25, 31)
        corner(track, 4)
        track.Parent = bb

        local fill = Instance.new("Frame")
        fill.Size = UDim2.fromScale(1, 1)
        fill.BackgroundColor3 = Color3.fromRGB(85, 220, 110)
        fill.BorderSizePixel = 0
        corner(fill, 4)
        fill.Parent = track

        local numbers = Instance.new("TextLabel")
        numbers.Size = UDim2.fromScale(1, 1)
        numbers.BackgroundTransparency = 1
        numbers.TextColor3 = Color3.new(1, 1, 1)
        numbers.TextStrokeTransparency = 0.1
        numbers.TextSize = 10
        numbers.Font = Enum.Font.GothamBold
        numbers.ZIndex = 2
        numbers.Parent = track

        local record = {gui=bb, name=name, fill=fill, numbers=numbers}
        markers[plr] = record
        return record
    end

    local function update()
        local seen = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= Player then
                local character = plr.Character
                local h = character and character:FindFirstChildOfClass("Humanoid")
                local head = character and character:FindFirstChild("Head")
                if h and head and h.Health > 0 then
                    seen[plr] = true
                    local rec = markers[plr]
                    if not rec or not rec.gui.Parent or rec.gui.Adornee ~= head then
                        removeMarker(plr)
                        rec = makeMarker(plr, head)
                    end
                    local maxHP = math.max(h.MaxHealth, 1)
                    local hp = math.clamp(h.Health, 0, maxHP)
                    local fraction = hp / maxHP
                    rec.fill.Size = UDim2.fromScale(fraction, 1)
                    rec.fill.BackgroundColor3 = fraction > 0.5 and Color3.fromRGB(75, 220, 110)
                        or (fraction > 0.25 and Color3.fromRGB(245, 190, 60) or Color3.fromRGB(240, 65, 75))
                    rec.name.Text = plr.DisplayName
                    rec.numbers.Text = string.format("%d / %d", math.ceil(hp), math.ceil(maxHP))
                end
            end
        end
        for plr in pairs(markers) do
            if not seen[plr] then removeMarker(plr) end
        end
    end

    persistentToggle(toggle, function()
        enabled = not enabled
        toggle.Text = enabled and "HEALTH BARS: ON" or "HEALTH BARS: OFF"
        animateToggle(toggle, enabled)
        if enabled then update() else removeAll() end
    end)
    toggle.Text = "HEALTH BARS: OFF"
    animateToggle(toggle, false)

    local elapsed = 0
    bindGlobal(RunService.Heartbeat, function(dt)
        if not enabled then return end
        elapsed += dt
        if elapsed >= 0.125 then
            elapsed = 0
            update()
        end
    end)
    bindGlobal(Players.PlayerRemoving, removeMarker)
    Gui.Destroying:Connect(removeAll)
end

local function setESP(on)
	State.ESP = on
	espToggle.Text = on and "ON" or "OFF"
	animateToggle(espToggle, on)
	if not on then
		for plr, hl in pairs(espHighlights) do
			if hl then hl:Destroy() end
			espHighlights[plr] = nil
		end
	end
end

local function setTracers(on)
	State.Tracers = on
	tracersToggle.Text = on and "ON" or "OFF"
	animateToggle(tracersToggle, on)
	if not on then
		for plr, line in pairs(tracerLines) do
			if line then line:Destroy() end
			tracerLines[plr] = nil
		end
	end
end

persistentToggle(espToggle, function()
	setESP(not State.ESP)
end)

persistentToggle(tracersToggle, function()
	setTracers(not State.Tracers)
end)

local function startBind(which)
	waitingForBind = which
	if which == "ESP" then
		espBindBtn.Text = "Press a key..."
		espBindBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		espBindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		tracersBindBtn.Text = "Press a key..."
		tracersBindBtn.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
		tracersBindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

espBindBtn.Activated:Connect(function()
	startBind("ESP")
end)

tracersBindBtn.Activated:Connect(function()
	startBind("Tracers")
end)

bindGlobal(UIS.InputBegan, function(input, gpe)
	if waitingForBind then
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local code = input.KeyCode
			if code == Enum.KeyCode.Escape then
				if waitingForBind == "ESP" then
					State.ESPBind = nil
					espBindBtn.Text = "Bind: None"
				else
					State.TracersBind = nil
					tracersBindBtn.Text = "Bind: None"
				end
			else
				if waitingForBind == "ESP" then
					State.ESPBind = code
					espBindBtn.Text = "Bind: " .. keyName(code)
				else
					State.TracersBind = code
					tracersBindBtn.Text = "Bind: " .. keyName(code)
				end
			end
			if waitingForBind == "ESP" then
				espBindBtn.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
				espBindBtn.TextColor3 = Color3.fromRGB(40, 42, 55)
			else
				tracersBindBtn.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
				tracersBindBtn.TextColor3 = Color3.fromRGB(40, 42, 55)
			end
			waitingForBind = nil
            queueUISave()
		end
		return
	end

	if gpe then return end
	if UIS:GetFocusedTextBox() then return end

	if State.ESPBind and input.KeyCode == State.ESPBind then
		setESP(not State.ESP)
	elseif State.TracersBind and input.KeyCode == State.TracersBind then
		setTracers(not State.Tracers)
	end
end)

local function clearHeadLabels()
	for plr, gui in pairs(headLabels) do
		if gui then gui:Destroy() end
		headLabels[plr] = nil
	end
end

local function updateHeadLabel(plr, text, color)
	local existing = headLabels[plr]
	local char = plr.Character
	local head = char and char:FindFirstChild("Head")

	if not text or not head then
		if existing then
			existing:Destroy()
			headLabels[plr] = nil
		end
		return
	end

	if existing and existing.Parent and existing.Adornee == head then
		local lbl = existing:FindFirstChildWhichIsA("TextLabel")
		if lbl then
            if lbl.Text ~= text then lbl.Text = text end
            if lbl.TextColor3 ~= color then lbl.TextColor3 = color end
		end
		return
	end

	if existing then
		existing:Destroy()
		headLabels[plr] = nil
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "VoidHubWLLabel"
	bb.AlwaysOnTop = true
	bb.MaxDistance = 170
	bb.Size = UDim2.fromOffset(176, 30)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	bb.Adornee = head
	-- Parent BillboardGui directly to PlayerGui so it reliably renders above heads.
	bb.Parent = PlayerGui

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.4
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.Parent = bb

	headLabels[plr] = bb
end

local function refreshListLabels()
	if not State.ShowWhitelist and not State.ShowBlacklist then
		clearHeadLabels()
		return
	end
	local seen = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Player then
			seen[plr] = true
            -- Whitelisted players remain protected from Freeze, even if a
            -- Blacklist fragment or ALL is present. Reflect that in head tags.
            if inPlayerList(State.Whitelist, plr) then
                if State.ShowWhitelist then
                    updateHeadLabel(plr, "WHITELISTED", Color3.fromRGB(95, 242, 142))
                else
                    updateHeadLabel(plr, nil, nil)
                end
            elseif State.ShowBlacklist and isBad(plr) then
                updateHeadLabel(plr, "BLACKLISTED", Color3.fromRGB(255, 85, 85))
            else
				-- Unlisted players have no overhead label.
				updateHeadLabel(plr, nil, nil)
			end
		end
	end
	for plr in pairs(headLabels) do
		if not seen[plr] then
			updateHeadLabel(plr, nil, nil)
		end
	end
end

local wlPage = pages["Attack"]

-- Unified player list section; original list-sync and matching logic is unchanged.
local playerListsCard = Instance.new("Frame")
playerListsCard.Name = "PlayerListsCombined"
playerListsCard.Position = UDim2.fromOffset(0, 238)
playerListsCard.Size = UDim2.fromOffset(880, 182)
playerListsCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
playerListsCard.BorderSizePixel = 0
corner(playerListsCard, 10)
stroke(playerListsCard, Color3.fromRGB(210, 214, 225), 1)
playerListsCard.Parent = wlPage

local listsTitle = Instance.new("TextLabel")
listsTitle.Name = "PlayerListsTitle"
listsTitle.Position = UDim2.fromOffset(16, 5)
listsTitle.Size = UDim2.fromOffset(846, 23)
listsTitle.BackgroundTransparency = 1
listsTitle.Font = Enum.Font.GothamBold
listsTitle.TextSize = 14
listsTitle.TextColor3 = Color3.fromRGB(30, 32, 40)
listsTitle.TextXAlignment = Enum.TextXAlignment.Left
listsTitle.Text = "PLAYER LISTS   |   WHITELIST + BLACKLIST"
listsTitle.Parent = playerListsCard

local function makeListCard(parent, title, x)
	local card = Instance.new("Frame")
	card.Size = UDim2.fromOffset(414, 144)
	card.Position = UDim2.fromOffset(x, 30)
	card.BackgroundColor3 = Color3.fromRGB(246, 248, 252)
	card.BorderSizePixel = 0
	corner(card, 10)
	stroke(card, Color3.fromRGB(210, 214, 225), 1)
	card.Parent = parent

	local titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Position = UDim2.fromOffset(14, 5)
	titleLbl.Size = UDim2.fromOffset(230, 22)
	titleLbl.Font = Enum.Font.GothamBold
	titleLbl.Text = title
	titleLbl.TextColor3 = Color3.fromRGB(30, 32, 40)
	titleLbl.TextSize = 15
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Parent = card

	local box = Instance.new("TextBox")
	box.Size = UDim2.fromOffset(382, 34)
	box.Position = UDim2.fromOffset(16, 35)
	box.BackgroundColor3 = Color3.fromRGB(240, 242, 248)
	box.Text = ""
	box.PlaceholderText = "Username, display name or unique part (e.g. Void, Slayer)"
	box.PlaceholderColor3 = Color3.fromRGB(150, 155, 170)
	box.TextColor3 = Color3.fromRGB(30, 32, 40)
	box.TextSize = 13
	box.Font = Enum.Font.Gotham
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Left
	corner(box, 8)
	stroke(box, Color3.fromRGB(210, 214, 225), 1)
	box.Parent = card

	local showBtn = Instance.new("TextButton")
	showBtn.Size = UDim2.fromOffset(150, 32)
	showBtn.Position = UDim2.fromOffset(16, 78)
	showBtn.BackgroundColor3 = Color3.fromRGB(230, 232, 240)
	showBtn.Text = "Show " .. string.lower(title)
	showBtn.TextColor3 = Color3.fromRGB(40, 42, 55)
	showBtn.TextSize = 12
	showBtn.Font = Enum.Font.GothamBold
	showBtn.AutoButtonColor = false
	corner(showBtn, 8)
	showBtn.Parent = card

	local listLbl = Instance.new("TextLabel")
	listLbl.BackgroundTransparency = 1
	listLbl.Position = UDim2.fromOffset(16, 115)
	listLbl.Size = UDim2.fromOffset(382, 23)
	listLbl.Font = Enum.Font.Gotham
	listLbl.Text = "Empty"
	listLbl.TextColor3 = Color3.fromRGB(120, 125, 140)
	listLbl.TextSize = 12
	listLbl.TextXAlignment = Enum.TextXAlignment.Left
	listLbl.TextYAlignment = Enum.TextYAlignment.Top
	listLbl.TextWrapped = true
	listLbl.Parent = card

	return card, box, showBtn, listLbl
end

local wlCard, wlBox, showWlBtn, wlListLbl = makeListCard(playerListsCard, "Whitelist", 8)
local blCard, blBox, showBlBtn, blListLbl = makeListCard(playerListsCard, "Blacklist", 458)
wlBox.PlaceholderText = "Protect groups: tmk, rng, og (matches ALL names containing each)"

-- The shared inputs also control the imported Carry/Freeze tools below.
local sharedListInfo = Instance.new("TextLabel")
sharedListInfo.Name = "SharedListInfo"
sharedListInfo.BackgroundTransparency = 1
sharedListInfo.Position = UDim2.fromOffset(4, 425)
sharedListInfo.Size = UDim2.fromOffset(874, 43)
sharedListInfo.Font = Enum.Font.Gotham
sharedListInfo.TextColor3 = Color3.fromRGB(57, 64, 82)
sharedListInfo.TextSize = 12
sharedListInfo.TextWrapped = true
sharedListInfo.TextXAlignment = Enum.TextXAlignment.Left
sharedListInfo.TextYAlignment = Enum.TextYAlignment.Center
sharedListInfo.Text = "WHITELIST GROUPS: tmk, rng, og protect ALL usernames/display names containing each fragment (case-insensitive). Protects from Bring + Freeze; Blacklist matching stays unchanged."
sharedListInfo.Parent = wlPage

local function updateListLabel(dict, label)
	local names = {}
	for name in pairs(dict) do
		table.insert(names, name)
	end
	table.sort(names)
	if #names == 0 then
		label.Text = "Empty"
		label.TextColor3 = Color3.fromRGB(120, 125, 140)
	else
		label.Text = table.concat(names, ", ")
		label.TextColor3 = Color3.fromRGB(30, 32, 40)
	end
end

local function syncCarryLists()
    local trusted = parseNames(wlBox.Text)
    local bad = parseNames(blBox.Text)
    table.clear(State.Whitelist)
    table.clear(State.Blacklist)
    for name in pairs(bad) do State.Blacklist[name] = true end
    for name in pairs(trusted) do State.Whitelist[name] = true end
    updateListLabel(State.Whitelist, wlListLbl)
    updateListLabel(State.Blacklist, blListLbl)
    refreshListLabels()
end

local function syncWhitelistFromBox() syncCarryLists() end
local function syncBlacklistFromBox() syncCarryLists() end

-- The previous version rebuilt every overhead label for EACH typed character.
-- Update after the user pauses typing, or immediately on leaving the box.
local listEditRevision = 0
local function scheduleListSync()
    listEditRevision += 1
    local revision = listEditRevision
    task.delay(0.30, function()
        if Gui.Parent and revision == listEditRevision then
            syncCarryLists()
        end
    end)
end
wlBox:GetPropertyChangedSignal("Text"):Connect(scheduleListSync)
blBox:GetPropertyChangedSignal("Text"):Connect(scheduleListSync)
wlBox.FocusLost:Connect(syncCarryLists)
blBox.FocusLost:Connect(syncCarryLists)
savedApply[#savedApply + 1] = syncCarryLists

local function setShowWhitelist(on)
	State.ShowWhitelist = on
	showWlBtn.Text = on and "Hide whitelist" or "Show whitelist"
	animateToggle(showWlBtn, on)
	refreshListLabels()
end

local function setShowBlacklist(on)
	State.ShowBlacklist = on
	showBlBtn.Text = on and "Hide blacklist" or "Show blacklist"
	animateToggle(showBlBtn, on)
	refreshListLabels()
end

showWlBtn.Activated:Connect(function()
	setShowWhitelist(not State.ShowWhitelist)
end)

showBlBtn.Activated:Connect(function()
	setShowBlacklist(not State.ShowBlacklist)
end)

-- Both head tag categories start enabled. Synchronize their button captions.
setShowWhitelist(State.ShowWhitelist)
setShowBlacklist(State.ShowBlacklist)

-- V100 VISUALS FIX: ESP and Tracers must show all other players regardless
-- of the Attack blacklist/whitelist. Those lists are for attack targeting.
local function shouldVisualize(plr)
    return plr ~= Player and plr ~= nil and plr:IsA("Player") and plr.Parent == Players
end

local function getRoot(plr)
    local char = plr and plr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function removeESP(plr)
    local hl = espHighlights[plr]
    if hl then
        hl:Destroy()
        espHighlights[plr] = nil
    end
end

local function ensureESP(plr)
    if not shouldVisualize(plr) then
        removeESP(plr)
        return
    end
    local char = plr.Character
    if not char or not char:IsDescendantOf(workspace) then
        removeESP(plr)
        return
    end

    local hl = espHighlights[plr]
    if hl and hl.Parent == char and hl.Adornee == char then
        if not hl.Enabled then hl.Enabled = true end
        return
    end
    removeESP(plr)

    hl = Instance.new("Highlight")
    hl.Name = "VoidHubESP"
    hl.Adornee = char  -- Explicitly target the live model, including after respawn.
    hl.Enabled = true
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = Color3.fromRGB(255, 255, 255)
    hl.OutlineColor = Color3.fromRGB(0, 0, 0)
    hl.FillTransparency = 0.72
    hl.OutlineTransparency = 0
    hl.Parent = char
    espHighlights[plr] = hl
end

-- Screen-space tracer overlay, which shares the same full-screen dimensions
-- as our ScreenGui (IgnoreGuiInset = true). Never covers hub controls.
local tracerCanvas = Instance.new("Frame")
tracerCanvas.Name = "VoidHubTracerCanvas"
tracerCanvas.BackgroundTransparency = 1
tracerCanvas.BorderSizePixel = 0
tracerCanvas.Size = UDim2.fromScale(1, 1)
tracerCanvas.Position = UDim2.fromScale(0, 0)
tracerCanvas.ClipsDescendants = true
tracerCanvas.ZIndex = 2
tracerCanvas.Active = false
tracerCanvas.Parent = Gui

local function removeTracer(plr)
    local line = tracerLines[plr]
    if line then
        line:Destroy()
        tracerLines[plr] = nil
    end
end

local function ensureTracer(plr)
    if not shouldVisualize(plr) then
        removeTracer(plr)
        return
    end
    local line = tracerLines[plr]
    if line and line.Parent == tracerCanvas then return end
    removeTracer(plr)

    line = Instance.new("Frame")
    line.Name = "VoidHubTracer"
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    line.BackgroundTransparency = 0.04
    line.BorderSizePixel = 0
    local blackEdge = Instance.new("UIStroke")
    blackEdge.Name = "BlackTracerOutline"
    blackEdge.Color = Color3.fromRGB(0, 0, 0)
    blackEdge.Thickness = 1
    blackEdge.Transparency = 0
    blackEdge.Parent = line
    line.ZIndex = 2
    line.Visible = false
    line.Parent = tracerCanvas
    tracerLines[plr] = line
end

local function updateTracers()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local viewport = cam.ViewportSize
    if viewport.X < 10 or viewport.Y < 10 then return end

    -- A stable on-screen origin prevents lines from disappearing when the
    -- local character is behind/under the camera or still respawning.
    local a = Vector2.new(viewport.X * 0.5, viewport.Y - 24)
    for plr, line in pairs(tracerLines) do
        if not State.Tracers or not shouldVisualize(plr) then
            removeTracer(plr)
            continue
        end
        local root = getRoot(plr)
        if not root or not root:IsDescendantOf(workspace) then
            line.Visible = false
            continue
        end

        local projected = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 1.6, 0))
        if projected.Z <= 0 then
            line.Visible = false -- Behind the camera; avoid mirrored artifacts.
            continue
        end

        -- The end can sit at the edge when a player is slightly offscreen.
        local b = Vector2.new(
            math.clamp(projected.X, 8, viewport.X - 8),
            math.clamp(projected.Y, 8, viewport.Y - 8)
        )
        local v = b - a
        local length = v.Magnitude
        if length < 2 then
            line.Visible = false
            continue
        end
        line.Size = UDim2.fromOffset(length, 2.5)
        line.Position = UDim2.fromOffset((a.X + b.X) * 0.5, (a.Y + b.Y) * 0.5)
        line.Rotation = math.deg(math.atan2(v.Y, v.X))
        line.Visible = true
    end
end

-- Fast screen-space updates without rescanning all players on every frame.
-- Rebuild lists at 4 Hz for new joins/respawns, draw lines at up to 30 Hz.
local lastTagRefresh = 0
local lastEspRefresh = 0
local lastTracerRefresh = 0
local lastTracerDraw = 0
bindGlobal(RunService.Heartbeat, function()
    if not Gui.Parent then return end
    local now = os.clock()

    if State.ESP and now - lastEspRefresh >= 0.25 then
        lastEspRefresh = now
        for _, plr in ipairs(Players:GetPlayers()) do ensureESP(plr) end
        for plr in pairs(espHighlights) do
            if not shouldVisualize(plr) then removeESP(plr) end
        end
    end

    if State.Tracers then
        if now - lastTracerRefresh >= 0.25 then
            lastTracerRefresh = now
            for _, plr in ipairs(Players:GetPlayers()) do ensureTracer(plr) end
        end
        if now - lastTracerDraw >= 1 / 30 then
            lastTracerDraw = now
            updateTracers()
        end
    end

    if (State.ShowWhitelist or State.ShowBlacklist) and now - lastTagRefresh >= 1.4 then
        lastTagRefresh = now
        refreshListLabels()
    end
end)

bindGlobal(Players.PlayerRemoving, function(plr)
	if espHighlights[plr] then
		espHighlights[plr]:Destroy()
		espHighlights[plr] = nil
	end
	if tracerLines[plr] then
		tracerLines[plr]:Destroy()
		tracerLines[plr] = nil
	end
	if headLabels[plr] then
		headLabels[plr]:Destroy()
		headLabels[plr] = nil
	end
end)

local Launcher = Instance.new("TextButton")
Launcher.Name = "VoidHubLauncher"
Launcher.Size = UDim2.fromOffset(58, 58)
Launcher.Position = UDim2.new(0, 18, 1, -78)
Launcher.BackgroundColor3 = Color3.fromRGB(245, 246, 250)
Launcher.Text = "V"
Launcher.TextColor3 = Color3.fromRGB(40, 42, 55)
Launcher.TextSize = 25
Launcher.Font = Enum.Font.GothamBlack
Launcher.Visible = true
Launcher.ZIndex = 50
corner(Launcher, 29)
Launcher.Parent = Gui

local panelOpen = true

local function setPanel(open)
	panelOpen = open == true
	Gui.Enabled = true
	Launcher.Visible = true
	Holder.Visible = panelOpen
	Main.Visible = panelOpen
	if panelOpen then
		updatePanelScale()
	end
end

Launcher.Activated:Connect(function()
	setPanel(not panelOpen)
end)

bindGlobal(UIS.InputBegan, function(input, gpe)
	if waitingForBind then return end
	if gpe then return end
	if UIS:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.LeftControl then
		setPanel(not panelOpen)
	end
end)

do
	local draggingPanel = false
	local dragPointer = nil
	local dragStart = nil
	local holderStart = nil

	Main.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
        -- Only the 46px title bar is draggable; controls and scroll views are not.
        local topBarY = (input.Position.Y - Main.AbsolutePosition.Y) / math.max(PanelScale.Scale, 0.01)
        if topBarY < 0 or topBarY > 46 then return end
		draggingPanel = true
		dragPointer = input
		dragStart = input.Position
		holderStart = Holder.Position
	end)

	local function cancelDrag(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			draggingPanel = false
			dragPointer = nil
			dragStart = nil
			holderStart = nil
		end
	end

	KillBtn.InputBegan:Connect(cancelDrag)
	SizeDownBtn.InputBegan:Connect(cancelDrag)
	SizeUpBtn.InputBegan:Connect(cancelDrag)
	for _, b in pairs(segmentButtons) do
		b.InputBegan:Connect(cancelDrag)
	end
	espToggle.InputBegan:Connect(cancelDrag)
	espBindBtn.InputBegan:Connect(cancelDrag)
	tracersToggle.InputBegan:Connect(cancelDrag)
	tracersBindBtn.InputBegan:Connect(cancelDrag)
	showWlBtn.InputBegan:Connect(cancelDrag)
	showBlBtn.InputBegan:Connect(cancelDrag)

	bindGlobal(UIS.InputChanged, function(input)
		if not draggingPanel or not dragStart or not holderStart then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragPointer then
			return
		end

		local camera = workspace.CurrentCamera
		if not camera then return end
		local viewport = camera.ViewportSize
		if viewport.X <= 0 or viewport.Y <= 0 then return end

		local delta = input.Position - dragStart
		local halfWidth = Holder.Size.X.Offset * PanelScale.Scale / 2
		local halfHeight = Holder.Size.Y.Offset * PanelScale.Scale / 2

		local cx = viewport.X * holderStart.X.Scale + holderStart.X.Offset + delta.X
		local cy = viewport.Y * holderStart.Y.Scale + holderStart.Y.Offset + delta.Y

		cx = math.clamp(cx, halfWidth + 10, math.max(halfWidth + 10, viewport.X - halfWidth - 10))
		cy = math.clamp(cy, halfHeight + 10, math.max(halfHeight + 10, viewport.Y - halfHeight - 10))

		Holder.Position = UDim2.fromScale(cx / viewport.X, cy / viewport.Y)
	end)

	bindGlobal(UIS.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input == dragPointer then
			draggingPanel = false
			dragPointer = nil
			dragStart = nil
			holderStart = nil
		end
	end)
end

do
	local dragging = false
	local dragStart
	local startPos

	Launcher.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = Launcher.Position
		end
	end)

	bindGlobal(UIS.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			Launcher.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	bindGlobal(UIS.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end


-- =====================================================================
-- BEGIN FREEZE(3).TXT ORIGINAL FUNCTIONS (EXACT)
-- =====================================================================
do
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- In an owned Roblox project the High School Experience RP remotes may not exist.
-- Hide only the game-specific imported Carry/Freeze adapter in that case.
-- Server-owned Freeze 8 is inserted in the same Attack tab just below this block.
local legacyRemotes = ReplicatedStorage:FindFirstChild("Remotes")
local legacyAvailable = legacyRemotes
    and legacyRemotes:FindFirstChild("onEnterCombat")
    and legacyRemotes:FindFirstChild("ReplicateParticle")
    and ReplicatedStorage:FindFirstChild("DeclineRequest")
    and ReplicatedStorage:FindFirstChild("CarryStarted")
    and ReplicatedStorage:FindFirstChild("SendRequestGui")
    and ReplicatedStorage:FindFirstChild("StopCarry")
    and ReplicatedStorage:FindFirstChild("TogglePrompts")
    and ReplicatedStorage:FindFirstChild("CarryRequest")
if legacyAvailable and not ReplicatedStorage:FindFirstChild("VH_FreezeAll_Control") then
local Remotes = legacyRemotes
local onEnterCombat = Remotes.onEnterCombat
local ReplicateParticle = Remotes.ReplicateParticle
local DeclineRequest = ReplicatedStorage.DeclineRequest
local CarryStarted = ReplicatedStorage.CarryStarted
local SendRequestGui = ReplicatedStorage.SendRequestGui
local StopCarry = ReplicatedStorage.StopCarry
local TogglePrompts = ReplicatedStorage.TogglePrompts
local CarryRequest = ReplicatedStorage.CarryRequest
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local SAVE = {}
local function Get(k, d) return SAVE[k] ~= nil and SAVE[k] or d end
local function Set(k, v) SAVE[k] = v end

local function parseList(str)
    local t = {}
    if str == "" then return t end
    for w in str:gmatch("%S+") do table.insert(t, w:lower()) end
    return t
end

local function isTarget(n, targetList)
    if #targetList == 0 then return true end
    local ln = n:lower()
    for _, v in ipairs(targetList) do
        if ln:find(v, 1, true) then return true end
    end
    return false
end

local function isSafe(n, safeList)
    local ln = n:lower()
    for _, v in ipairs(safeList) do
        if ln:find(v, 1, true) then return true end
    end
    return false
end

-- ============================================
-- AUTO DECLINE CODE
-- ============================================
local autoDeclineConnections = {}
-- Shared recovery signal lets Auto Decline Requests protect against an
-- actual incoming freeze even when the outgoing Freeze toggle is enabled.
local declineRecoveryUntil = 0
local declineStats = {
    requests = 0,
    carries = 0,
    guis = 0,
    prompts = 0
}

local function GetDeclineStats()
    return declineStats
end

local function ResetDeclineStats()
    declineStats = {requests = 0, carries = 0, guis = 0, prompts = 0}
end

-- Both Auto Decline toggles share the same incoming-carry protection.
-- An ordinary decline event is only a request: the server may still move us.
local function declineProtectionEnabled()
    return Get("AutoDecline", false) or Get("AutoDeclineRequests", false)
end

local function StartAutoDecline()
    -- Event-driven rejection: never spam requests every rendered frame.
    for _, connection in pairs(autoDeclineConnections) do
        if connection then connection:Disconnect() end
    end
    autoDeclineConnections = {}
    ResetDeclineStats()

    local lastSafePivot, lastSafeAt = nil, 0
    local sampled = 0
    local recoverUntil, lastReject = 0, -math.huge
    local lockedPivot, lockedCharacter = nil, nil
    local lastRecoveryCorrection = -math.huge
    local lastGetUpAt = -math.huge
    local healthyWalkSpeed, healthyJumpPower, healthyJumpHeight = nil, nil, nil
    local RECOVER_WINDOW = 0.70
    local GET_UP_COOLDOWN = 0.15
    local token, active = 0, true
    declineRecoveryUntil = 0

    local function requesterFrom(...)
        for i = 1, select("#", ...) do
            local candidate = select(i, ...)
            if typeof(candidate) == "Instance" and candidate:IsA("Player") and candidate ~= player then
                return candidate
            end
        end
        return nil
    end

    local function protectedRequester(...)
        local requester = requesterFrom(...)
        if not requester then return false end
        local names = parseList(Get("DeclineWhitelist", ""))
        return #names > 0 and
            (isSafe(requester.Name, names) or isSafe(requester.DisplayName, names))
    end

    local function isOwnAction()
        -- Do not reposition/decline during your own Forcefield, Bring or Death TP.
        return DeathTPIsEscaping or SharedTeleportOwner ~= nil
            or isManualGrabWindow()
            or os.clock() < AntiTPIntentionalTeleportUntil
    end

    local function releaseCharacter(savedPivot)
        if not active or not declineProtectionEnabled() or isOwnAction() then return end
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not hum or not root or hum.Health <= 0 then return end
        local now = os.clock()
        local recovering = lockedCharacter == char and now < recoverUntil
        local state = hum:GetState()
        local locked = hum.PlatformStand or hum.Sit or root.Anchored
        local physicsLocked = state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.Ragdoll
        local speedLocked = recovering and healthyWalkSpeed and healthyWalkSpeed > 0.5
            and hum.WalkSpeed < 0.5
        local jumpPowerLocked = recovering and hum.UseJumpPower
            and healthyJumpPower and healthyJumpPower > 0
            and hum.JumpPower <= 0
        local jumpHeightLocked = recovering and not hum.UseJumpPower
            and healthyJumpHeight and healthyJumpHeight > 0
            and hum.JumpHeight <= 0
        if locked or (recovering and physicsLocked) or speedLocked
            or jumpPowerLocked or jumpHeightLocked then
            pcall(function()
                if root.Anchored then root.Anchored = false end
                if hum.PlatformStand then hum.PlatformStand = false end
                if hum.Sit then hum.Sit = false end
                if speedLocked then hum.WalkSpeed = healthyWalkSpeed end
                if jumpPowerLocked then hum.JumpPower = healthyJumpPower end
                if jumpHeightLocked then hum.JumpHeight = healthyJumpHeight end
                -- Avoid restarting GettingUp every rendered frame, which can
                -- itself make the avatar unable to walk.
                if (locked or physicsLocked) and now - lastGetUpAt >= GET_UP_COOLDOWN then
                    lastGetUpAt = now
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                end
            end)
        end
        -- Correct only a genuinely large server displacement during
        -- incoming recovery, never hold the character at one position.
        if savedPivot and recovering then
            local moveIntent = hum.MoveDirection.Magnitude > 0.05
                or UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.A)
                or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.D)
                or UIS:IsKeyDown(Enum.KeyCode.Space)
            if moveIntent then
                recoverUntil = 0
                lockedPivot, lockedCharacter = nil, nil
                return
            end
            local distance = (root.Position - savedPivot.Position).Magnitude
            if distance >= 7 and distance <= 900
                and now - lastRecoveryCorrection >= 0.15 then
                lastRecoveryCorrection = now
                pcall(function()
                    char:PivotTo(savedPivot)
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
    end

    local function rejectCarry()
        if not active or not declineProtectionEnabled() or isOwnAction() then return end
        local now = os.clock()
        -- Resolve a real incoming request immediately, while coalescing
        -- duplicates instead of flooding the server with retries.
        if now - lastReject < 0.02 then return end
        lastReject = now
        recoverUntil = now + RECOVER_WINDOW -- bounded local recovery, no position lock
        declineRecoveryUntil = recoverUntil
        token += 1
        local current = token
        local char = player.Character
        local saved = (now - lastSafeAt < 0.40) and lastSafePivot or nil
        -- Fallback if we lack a recent stable snapshot. It may already be
        -- affected by the server, so never describe the correction as guaranteed.
        if not saved and char then
            pcall(function() saved = char:GetPivot() end)
        end
        lockedPivot = saved
        lockedCharacter = char
        pcall(function()
            StopCarry:FireServer()
            DeclineRequest:FireServer()
        end)
        releaseCharacter(saved)
        -- Physics/render-frame guards below handle delayed motion immediately.
        -- One late check is kept in case the server responds after this event.
        task.delay(0.14, function()
            if not active or token ~= current or player.Character ~= char then return end
            releaseCharacter(saved)
        end)
    end

    autoDeclineConnections.safepoint = RunService.Heartbeat:Connect(function(dt)
        if not active or not declineProtectionEnabled() then return end
        local now = os.clock()
        if now < recoverUntil then
            releaseCharacter(lockedPivot)
            return
        end
        lockedPivot, lockedCharacter = nil, nil
        sampled += dt
        if sampled < 0.016 or isOwnAction() then return end
        sampled = 0
        local char = player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if hum and root and hum.Health > 0 and not hum.PlatformStand
            and not hum.Sit and not root.Anchored
            and hum.FloorMaterial ~= Enum.Material.Air
            and root.AssemblyLinearVelocity.Magnitude < 85 then
            lastSafePivot = char:GetPivot()
            lastSafeAt = now
            if hum.WalkSpeed > 0.5 then healthyWalkSpeed = hum.WalkSpeed end
            if hum.JumpPower > 0 then healthyJumpPower = hum.JumpPower end
            if hum.JumpHeight > 0 then healthyJumpHeight = hum.JumpHeight end
        end
    end)
    -- Render frame only assists a large teleport correction; never pins
    -- normal movement or changes jump during an ordinary carry request.
    autoDeclineConnections.visualHold = RunService.RenderStepped:Connect(function()
        if active and declineProtectionEnabled() and os.clock() < recoverUntil then
            releaseCharacter(lockedPivot)
        end
    end)

    local function attachRecoveryListener(character)
        -- All per-character listeners are replaced after respawn.
        for _, key in ipairs({"recoveryState", "recoveryAnchor", "recoverySit",
            "recoveryPhysics", "recoverySpeed"}) do
            local connection = autoDeclineConnections[key]
            if connection then connection:Disconnect() end
            autoDeclineConnections[key] = nil
        end
        if not character then return end
        task.spawn(function()
            local hum = character:FindFirstChildOfClass("Humanoid")
                or character:WaitForChild("Humanoid", 5)
            local root = character:FindFirstChild("HumanoidRootPart")
                or character:WaitForChild("HumanoidRootPart", 5)
            if not active or not hum or not root or character ~= player.Character then return end
            local function checkImmobilization()
                if not active or not declineProtectionEnabled() or isOwnAction()
                    or player.Character ~= character or hum.Health <= 0 then return end
                local now = os.clock()
                local state = hum:GetState()
                local hardFrozen = hum.PlatformStand or root.Anchored
                    or state == Enum.HumanoidStateType.Physics
                    or state == Enum.HumanoidStateType.Ragdoll
                    or (hum.Sit and hum.SeatPart == nil)
                local askingToWalk = hum.MoveDirection.Magnitude > 0.05
                    or UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.A)
                    or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.D)
                local speedFrozen = healthyWalkSpeed and healthyWalkSpeed > 0.5
                    and hum.WalkSpeed < 0.5 and askingToWalk
                -- A freeze may arrive before CarryStarted or SendRequestGui.
                -- Detect genuinely immobilized states as well as those events.
                if Get("AutoDeclineRequests", false) and (hardFrozen or speedFrozen)
                    and now >= recoverUntil and now - lastReject >= 0.12 then
                    rejectCarry()
                elseif now < recoverUntil then
                    releaseCharacter(lockedPivot)
                end
            end
            autoDeclineConnections.recoveryState =
                hum:GetPropertyChangedSignal("PlatformStand"):Connect(checkImmobilization)
            autoDeclineConnections.recoveryAnchor =
                root:GetPropertyChangedSignal("Anchored"):Connect(checkImmobilization)
            autoDeclineConnections.recoverySit =
                hum:GetPropertyChangedSignal("Sit"):Connect(checkImmobilization)
            autoDeclineConnections.recoveryPhysics =
                hum.StateChanged:Connect(checkImmobilization)
            autoDeclineConnections.recoverySpeed =
                hum:GetPropertyChangedSignal("WalkSpeed"):Connect(checkImmobilization)
            -- Spawn into an ongoing carry/freeze: do not wait for an event.
            checkImmobilization()
        end)
    end

    autoDeclineConnections.character = player.CharacterAdded:Connect(function(character)
        token += 1
        lastSafePivot, lastSafeAt = nil, 0
        recoverUntil, declineRecoveryUntil = 0, 0
        lastGetUpAt = -math.huge
        healthyWalkSpeed, healthyJumpPower, healthyJumpHeight = nil, nil, nil
        lockedPivot, lockedCharacter = nil, nil
        attachRecoveryListener(character)
    end)
    attachRecoveryListener(player.Character)

    autoDeclineConnections.carryStarted = CarryStarted.OnClientEvent:Connect(function(...)
        if protectedRequester(...) then return end
        declineStats.carries += 1
        rejectCarry()
    end)

    autoDeclineConnections.sendRequestGui = SendRequestGui.OnClientEvent:Connect(function(...)
        if protectedRequester(...) then return end
        declineStats.guis += 1
        rejectCarry()
    end)

    autoDeclineConnections.declineRequest = player.ChildAdded:Connect(function(child)
        if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
            local name = child.Name:lower()
            if name:find("request") or name:find("invite") or name:find("accept") then
                declineStats.requests += 1
                rejectCarry()
            end
        end
    end)

    local lastPrompt = 0
    autoDeclineConnections.togglePrompts = TogglePrompts.OnClientEvent:Connect(function(...)
        if not active or not declineProtectionEnabled() then return end
        local now = os.clock()
        if now - lastPrompt < 0.3 then return end
        lastPrompt = now
        declineStats.prompts += 1
        pcall(function() TogglePrompts:FireServer(false) end)
    end)
    -- Disconnect delayed callbacks safely when the toggle is switched OFF.
    autoDeclineConnections.stop = { Disconnect = function()
        active = false
        token += 1
    end }
end

local function StopAutoDecline()
    for k, v in pairs(autoDeclineConnections) do
        if v then v:Disconnect() end
    end
    autoDeclineConnections = {}
    declineRecoveryUntil = 0
    ResetDeclineStats()
end

-- ============================================
-- AUTO SEND & ACCEPT CARRY REQUESTS CODE
-- ============================================
local autoSendAcceptConnections = {}

local function StartAutoSendAccept()
    if autoSendAcceptConnections.megaSpamLoop then
        autoSendAcceptConnections.megaSpamLoop:Disconnect()
    end
    
    if autoSendAcceptConnections.acceptIncoming then
        autoSendAcceptConnections.acceptIncoming:Disconnect()
    end
    
    -- Prioritize incoming eligible targets inside the existing capped request batch.
    -- Never send extra event-driven CarryRequests outside the rate limit.
    local priorityTarget = nil
    local function isReadyFreezeTarget(other)
        if not shouldFreezeTarget(other) then return false end
        local character = other.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        return root ~= nil and humanoid ~= nil and humanoid.Health > 0
    end

    -- Select a real Player from the incoming event (the Player is not
    -- guaranteed to be its first argument). Never target a protected player.
    autoSendAcceptConnections.acceptIncoming = SendRequestGui.OnClientEvent:Connect(function(...)
        local args = table.pack(...)
        local requester = nil
        for i = 1, args.n do
            local value = args[i]
            if typeof(value) == "Instance" and value:IsA("Player") then
                requester = value
                break
            end
        end
        if requester and isReadyFreezeTarget(requester) then
            priorityTarget = requester
        end
    end)
    
    -- Scan up to 1000 eligible targets, including stationary players.
    -- A requested 0.000000000000001-second threshold runs on Heartbeat,
    -- not at 1 quadrillion cycles per second. Server controls effects.
    -- Preserve the spaced remote batch to protect game stability.
    local FREEZE_CHECK_INTERVAL = 0.000000000000001
    local FREEZE_MAX_TRACKED_TARGETS = 1000
    local FREEZE_BATCH_INTERVAL = 0.08
    local FREEZE_MAX_REQUESTS_PER_BATCH = 6
    local checkElapsed = 0
    local batchElapsed = FREEZE_BATCH_INTERVAL -- respond on the first eligible frame
    local nextTargetIndex = 1
    autoSendAcceptConnections.megaSpamLoop = RunService.Heartbeat:Connect(function(dt)
        if isManualGrabWindow() then
            checkElapsed = 0
            batchElapsed = FREEZE_BATCH_INTERVAL
            return
        end
        if not next(State.Blacklist) then
            checkElapsed = 0
            batchElapsed = FREEZE_BATCH_INTERVAL
            return
        end
        checkElapsed += dt
        batchElapsed += dt
        if checkElapsed < FREEZE_CHECK_INTERVAL then return end
        checkElapsed = 0
        if batchElapsed < FREEZE_BATCH_INTERVAL then return end
        batchElapsed = 0
        local targets = {}
        for _, p in Players:GetPlayers() do
            if isReadyFreezeTarget(p) then
                targets[#targets + 1] = p
                if #targets >= FREEZE_MAX_TRACKED_TARGETS then break end
            end
        end
        if #targets == 0 then return end
        -- Give each player a turn instead of wasting a batch on duplicates.
        local requestsThisTick = math.min(FREEZE_MAX_REQUESTS_PER_BATCH, #targets)
        local requestsSent = 0
        if priorityTarget then
            local priority = priorityTarget
            priorityTarget = nil
            if isReadyFreezeTarget(priority) then
                pcall(function()
                    CarryRequest:FireServer(priority, 1, 0, 1, 0, 180, 0)
                end)
                requestsSent += 1
            end
        end
        while requestsSent < requestsThisTick do
            if nextTargetIndex > #targets then nextTargetIndex = 1 end
            local p = targets[nextTargetIndex]
            nextTargetIndex += 1
            if p and isReadyFreezeTarget(p) then
                pcall(function()
                    CarryRequest:FireServer(p, 1, 0, 1, 0, 180, 0)
                end)
            end
            requestsSent += 1
        end
    end)
end

local function StopAutoSendAccept()
    for k, v in pairs(autoSendAcceptConnections) do
        if v then v:Disconnect() end
    end
    autoSendAcceptConnections = {}
end

local function StartAutoDeclineRequests()
    if autoSendAcceptConnections.declineLoop then
        autoSendAcceptConnections.declineLoop:Disconnect()
    end
    
    local elapsed = 0.05 -- next eligible Heartbeat can send immediately
    local REQUEST_CHECK_INTERVAL = 0.000000000000001 -- frame-limited eligibility threshold
    local PERIODIC_DECLINE_INTERVAL = 0.05 -- bounded while waiting for events
    autoSendAcceptConnections.declineLoop = RunService.Heartbeat:Connect(function(dt)
        if not Get("AutoDeclineRequests", false) then return end
        if dt < REQUEST_CHECK_INTERVAL then return end
        elapsed += dt
        if elapsed < PERIODIC_DECLINE_INTERVAL then return end
        elapsed = 0
        -- Event-driven rejection is immediate; periodic rejections stay bounded.
        -- Do not stop your own Forcefield/Bring/Freeze.
        if SharedTeleportOwner or DeathTPIsEscaping or isManualGrabWindow()
            or os.clock() < AntiTPIntentionalTeleportUntil then return end
        -- Freeze may be ON simultaneously. Do not cancel our OWN outgoing
        -- Freeze traffic, but allow declines during a genuine incoming
        -- carry/immobilization recovery.
        if Get("AutoAcceptRequests", false)
            and os.clock() >= declineRecoveryUntil then return end
        pcall(function()
            StopCarry:FireServer()
            DeclineRequest:FireServer()
        end)
    end)
end

local function StopAutoDeclineRequests()
    if autoSendAcceptConnections.declineLoop then
        autoSendAcceptConnections.declineLoop:Disconnect()
        autoSendAcceptConnections.declineLoop = nil
    end
end

-- ============================================
-- SPAM CARRY REQUEST CODE
-- ============================================
local spamCarryConnections = {}

local function StartSpamCarry()
    if spamCarryConnections.spamLoop then
        spamCarryConnections.spamLoop:Disconnect()
    end
    
    local elapsed = 0
    spamCarryConnections.spamLoop = RunService.Heartbeat:Connect(function(dt)
        if not Get("SpamCarry", false) or isManualGrabWindow() then return end
        elapsed = elapsed + dt
        if elapsed < 0.25 then return end
        elapsed = 0
        local targetName = Get("SpamCarryTarget", "")
        if targetName == "" then return end
        local targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer or not shouldFreezeTarget(targetPlayer) then return end
        pcall(function()
            CarryRequest:FireServer(targetPlayer, 1, 0, 1, 0, 180, 0)
        end)
    end)
end

local function StopSpamCarry()
    if spamCarryConnections.spamLoop then
        spamCarryConnections.spamLoop:Disconnect()
        spamCarryConnections.spamLoop = nil
    end
end

-- =====================================================================
-- FREEZE(3).TXT: GUI ADAPTER ONLY
-- Only StartAutoSendAccept / StopAutoSendAccept were replaced; other imported functions are unchanged.
-- This adapter replaces only the standalone window (lines after GUI marker).
-- =====================================================================
local carryToolsPage = pages["Attack"]
carryToolsPage.CanvasSize = UDim2.fromOffset(0, 1505)

local function importedCard(name, title, x, y, w, h)
    local c = Instance.new("Frame")
    c.Name, c.Position, c.Size = name, UDim2.fromOffset(x,y), UDim2.fromOffset(w,h)
    c.BackgroundColor3, c.BorderSizePixel, c.Parent = Color3.fromRGB(255,255,255), 0, carryToolsPage
    corner(c, 10)
    stroke(c, Color3.fromRGB(210,214,225), 1)
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Heading"
    titleLabel.Position = UDim2.fromOffset(14,10)
    titleLabel.Size = UDim2.new(1,-28,0,25)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 15
    titleLabel.TextColor3 = Color3.fromRGB(30,32,40)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = c
    return c
end

local function importedLabel(parent, value, y, height, color)
    local t = Instance.new("TextLabel")
    t.Position = UDim2.fromOffset(14,y)
    t.Size = UDim2.new(1,-28,0,height or 22)
    t.BackgroundTransparency = 1
    t.Text, t.TextWrapped = value, true
    t.TextColor3 = color or Color3.fromRGB(91,96,113)
    t.TextSize = 11
    t.TextXAlignment, t.TextYAlignment = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    t.Font, t.Parent = Enum.Font.Gotham, parent
    return t
end

local function importedToggle(parent, label, key, y, cb)
    local current = Get(key, false)
    local textLabel = importedLabel(parent, label, y+8, 23, Color3.fromRGB(38,42,54))
    textLabel.Size = UDim2.new(1,-110,0,23)
    local button = Instance.new("TextButton")
    button.Name = key.."Toggle"
    button.Position = UDim2.new(1,-92,0,y)
    button.Size = UDim2.fromOffset(78,32)
    button.TextColor3 = Color3.new(1,1,1)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.Parent = parent
    corner(button,7)
    local function redraw()
        button.BackgroundColor3 = current and Color3.fromRGB(38,145,88) or Color3.fromRGB(99,105,124)
        button.Text = current and "ON" or "OFF"
    end
    redraw()
    persistentToggle(button, function()
        current = not current
        Set(key,current)
        redraw()
        cb(current)
    end)
end

local function importedField(parent, title, key, placeholder, y)
    importedLabel(parent,title,y,17)
    local field = Instance.new("TextBox")
    field.Name = key.."Field"
    field.Position = UDim2.fromOffset(14,y+18)
    field.Size = UDim2.new(1,-28,0,30)
    field.BackgroundColor3 = Color3.fromRGB(240,242,248)
    field.Text = Get(key, "")
    field.PlaceholderText = placeholder
    field.PlaceholderColor3 = Color3.fromRGB(135,140,155)
    field.TextColor3 = Color3.fromRGB(30,32,40)
    field.Font = Enum.Font.Gotham
    field.TextSize = 12
    field.TextXAlignment = Enum.TextXAlignment.Left
    field.ClearTextOnFocus = false
    field.BorderSizePixel = 0
    field.Parent = parent
    corner(field,7)
    stroke(field,Color3.fromRGB(215,219,230),1)
    field.FocusLost:Connect(function()
        Set(key, field.Text)
    end)
    return field
end

-- Only the status label is needed by the roster below. Scope all
-- header/buttons/card locals separately to release registers before
-- constructing the monitor's UIListLayout (old compile failure at 6130).
local freezeStatusLabel
do
local head = Instance.new("TextLabel")
head.Name = "Freeze3Header"
head.Position = UDim2.fromOffset(0,489)
head.Size = UDim2.fromOffset(880,30)
head.BackgroundTransparency = 1
head.Text = "FREEZE / CARRY TOOLS  |  Whitelist protects Bring + Freeze"
head.Font = Enum.Font.GothamBold
head.TextSize = 13
head.TextXAlignment = Enum.TextXAlignment.Left
head.TextColor3 = Color3.fromRGB(40,42,55)
head.Parent = carryToolsPage

local decline = importedCard("OriginalDecline", "AUTO DECLINE", 0,527,430,212)
importedToggle(decline, "Enable Auto Decline", "AutoDecline", 43, function(v)
    if v then
        StartAutoDecline()
    elseif not Get("AutoDeclineRequests", false) then
        StopAutoDecline()
    end
end)
importedField(decline,"Decline whitelist (optional)","DeclineWhitelist","player1 player2",88)
importedLabel(decline,"Instant event rejection + bounded movement recovery. No standing-still lock.",149,55,Color3.fromRGB(156,73,32))

local accept = importedCard("OriginalAccept", "FREEZE / AUTO SEND", 450,527,430,255)
importedToggle(accept,"Enable new Carry loop", "AutoAcceptRequests", 43, function(v)
    if v then StartAutoSendAccept() else StopAutoSendAccept() end
end)
importedLabel(accept,"FREEZE: Blacklist targets; Whitelist groups (tmk, rng, og) protect all matching names.",89,46,Color3.fromRGB(38,110,74))
importedLabel(accept,"Up to 1000 targets; 0.000000000000001s threshold (Heartbeat-limited); 6 / 0.08s.",145,39,Color3.fromRGB(156,73,32))

-- V115: Update Freeze status and roster together in one scan.
freezeStatusLabel = importedLabel(accept,"FREEZE OFF  |  Checking targets...",192,54,Color3.fromRGB(77,84,103))
freezeStatusLabel.Name = "FreezeLiveTargetStatus"
freezeStatusLabel.Font = Enum.Font.GothamBold

local requests = importedCard("OriginalDeclineRequests","AUTO DECLINE REQUESTS",0,758,430,127)
importedToggle(requests,"Enable Auto Decline Requests", "AutoDeclineRequests",45,function(v)
    if v then
        if not Get("AutoDecline", false) then StartAutoDecline() end
        StartAutoDeclineRequests()
    else
        StopAutoDeclineRequests()
        if not Get("AutoDecline", false) then StopAutoDecline() end
    end
end)
importedLabel(requests,"Anti-freeze recovery: tracks anchored, Physics and zero speed; 0.05s bounded retries.",91,34)

local spam = importedCard("OriginalSpamCarry","SPAM CARRY",450,801,430,155)
importedToggle(spam,"Enable Spam Carry","SpamCarry",42,function(v)
    if v then StartSpamCarry() else StopSpamCarry() end
end)
importedField(spam,"Target username (exact)","SpamCarryTarget","exact Roblox username",88)

local stats = importedCard("OriginalStats","DECLINE STATS",0,975,880,107)
local statsLabel = importedLabel(stats,"Requests: 0  |  Carries: 0  |  GUIs: 0  |  Prompts: 0",51,30)
statsLabel.Name = "OriginalStatsLabel"
statsLabel.Font = Enum.Font.GothamBold
statsLabel.TextSize = 13
local lastRefresh = 0
bindGlobal(RunService.Heartbeat, function()
    if not carryToolsPage.Visible then return end
    local t = os.clock()
    if t-lastRefresh < 0.5 then return end
    lastRefresh=t
    local s=GetDeclineStats()
    statsLabel.Text=("Requests: %d   |   Carries: %d   |   GUIs: %d   |   Prompts: %d")
       :format(s.requests,s.carries,s.guis,s.prompts)
end)

importedLabel(carryToolsPage,
    "FREEZE uses the combined lists above: Whitelist = safe, Blacklist = target, ALL = all except safe. " ..
    "V66 limits repeated Carry/Decline requests for stability. All imported toggles start OFF. Target effects may differ from V65.",
    1099,77,Color3.fromRGB(156,73,32))
end -- GUI cards built; locals head/decline/accept/requests/spam/stats released

-- FREEZE TARGET MONITOR: displays up to 1000 players without sending
-- additional remote requests. It is informational, not a 1000-player server.
do
local freezeRoster = importedCard("Freeze100Monitor", "FREEZE PLAYER MONITOR  |  UP TO 1000", 0,1191,880,279)
local rosterSummary = importedLabel(freezeRoster, "Checking eligible players...", 42,23,Color3.fromRGB(70,77,96))
rosterSummary.Font = Enum.Font.GothamBold
local rosterScroll = Instance.new("ScrollingFrame")
rosterScroll.Name = "FreezeRosterScroll"
rosterScroll.Size = UDim2.new(1,-28,0,190)
rosterScroll.Position = UDim2.fromOffset(14,73)
rosterScroll.BackgroundColor3 = Color3.fromRGB(246,247,250)
rosterScroll.BorderSizePixel = 0
rosterScroll.ScrollBarThickness = 5
rosterScroll.ScrollingDirection = Enum.ScrollingDirection.Y
rosterScroll.CanvasSize = UDim2.fromOffset(0,0)
rosterScroll.Parent = freezeRoster
corner(rosterScroll, 7)
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0,3)
listLayout.Parent = rosterScroll
local rosterRows = {}
local rosterTime = 0
local function newRosterRow(i)
    local row = Instance.new("TextLabel")
    row.Name = "Player" .. tostring(i)
    row.Size = UDim2.new(1,-14,0,19)
    row.BackgroundTransparency = 1
    row.Font = Enum.Font.Gotham
    row.TextSize = 12
    row.TextXAlignment = Enum.TextXAlignment.Left
    row.TextColor3 = Color3.fromRGB(65,71,86)
    row.LayoutOrder = i
    row.Parent = rosterScroll
    rosterRows[i] = row
    return row
end
bindGlobal(RunService.Heartbeat, function(dt)
    if not carryToolsPage.Visible or not Gui.Parent then return end
    rosterTime = rosterTime + dt
    if rosterTime < 0.15 then return end
    rosterTime = 0

    local everyone = {}
    local protectedCount, targetCount = 0, 0
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player then
            local protected = inPlayerList(State.Whitelist, other)
            local eligible = shouldFreezeTarget(other)
            if protected then protectedCount = protectedCount + 1 end
            if eligible then targetCount = targetCount + 1 end
            local marker = protected and "PROTECTED" or (eligible and "TARGET" or "NOT LISTED")
            local tint = protected and Color3.fromRGB(23,117,75)
                or (eligible and Color3.fromRGB(164,88,25) or Color3.fromRGB(100,107,125))
            everyone[#everyone + 1] = {name=other.Name, marker=marker, tint=tint}
        end
    end
    table.sort(everyone, function(a,b) return a.name:lower() < b.name:lower() end)
    local shown = math.min(#everyone, 1000)
    for i=1,shown do
        local row = rosterRows[i] or newRosterRow(i)
        local item = everyone[i]
        local updated = item.name .. "  |  " .. item.marker
        if row.Text ~= updated then row.Text = updated end
        row.TextColor3 = item.tint
        row.Visible = true
    end
    for i=shown+1,#rosterRows do rosterRows[i].Visible = false end
    rosterScroll.CanvasSize = UDim2.fromOffset(0,math.max(190,shown*22+6))
    local freezeOn = Get("AutoAcceptRequests", false)
    rosterSummary.Text = ("Monitoring %d/%d players  |  %d eligible  |  %d protected  |  %s")
        :format(shown,#everyone,targetCount,protectedCount,freezeOn and "ON" or "OFF")
    local sample = {}
    for _, item in ipairs(everyone) do
        if item.marker == "TARGET" then
            sample[#sample+1] = item.name
            if #sample == 3 then break end
        end
    end
    local sampleText = table.concat(sample, ", ")
    if targetCount > #sample then sampleText = sampleText .. " +more" end
    if targetCount == 0 then
        sampleText = next(State.Blacklist) and "No eligible targets online" or "Add player to Blacklist (or ALL)"
    end
    freezeStatusLabel.Text = ("%s  |  %d targets  |  %d protected\n%s")
        :format(freezeOn and "FREEZE ON" or "FREEZE OFF",targetCount,protectedCount,sampleText)
    freezeStatusLabel.TextColor3 = freezeOn and
        (targetCount > 0 and Color3.fromRGB(34,130,84) or Color3.fromRGB(168,101,35))
        or Color3.fromRGB(77,84,103)
end)
end -- close Freeze roster lexical scope; listeners capture their own UI refs

-- Window integration cleanup. Freeze and SpamCarry target selection now
-- respect the shared whitelist/blacklist, leaving their Carry args unchanged.
Gui.Destroying:Connect(function()
    StopSpamCarry()
    StopAutoDeclineRequests()
    StopAutoSendAccept()
    StopAutoDecline()
end)
-- END ORIGINAL FREEZE(3).TXT GUI ADAPTER

end -- legacy carry / freeze adapter; no-op in owned games with server Freeze 30
end -- original adapter scope

-- ============================================================================
-- VOID HUB OWNER EDITION | FREEZE 30 INSIDE THE ORIGINAL ATTACK TAB
-- The server creates VH_FreezeAll_Control. This is NOT a remote-spam exploit.
-- Existing player whitelist / blacklist fields feed eligible player UserIds.
-- ============================================================================
do
    local ownerRemote = game:GetService("ReplicatedStorage"):WaitForChild("VH_FreezeAll_Control", 4)
    local attack = pages["Attack"]
    if ownerRemote and ownerRemote:IsA("RemoteEvent") and attack then
        attack.CanvasSize = UDim2.fromOffset(0, 890)
        local card = makeFeatureCard(attack, "FREEZE 30  |  SERVER EDITION", 527)
        card.Name = "OwnerFreeze30Card"
        card.Size = UDim2.fromOffset(880, 205)
        local info = Instance.new("TextLabel")
        info.Name = "Freeze30Instructions"
        info.BackgroundTransparency = 1
        info.Position = UDim2.fromOffset(16, 40)
        info.Size = UDim2.fromOffset(838, 48)
        info.TextWrapped = true
        info.Font = Enum.Font.Gotham
        info.TextSize = 12
        info.TextXAlignment = Enum.TextXAlignment.Left
        info.TextYAlignment = Enum.TextYAlignment.Top
        info.TextColor3 = Color3.fromRGB(65, 73, 91)
        info.Text = "Set Blacklist to ALL or selected player names above. Whitelist always protects. Freeze up to 30 eligible players on this game's server."
        info.Parent = card

        local freezeBtn = Instance.new("TextButton")
        freezeBtn.Name = "FreezeThirtyToggle"
        freezeBtn.Position = UDim2.fromOffset(16, 100)
        freezeBtn.Size = UDim2.fromOffset(228, 38)
        freezeBtn.BackgroundColor3 = Color3.fromRGB(40, 44, 55)
        freezeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        freezeBtn.Font = Enum.Font.GothamBold
        freezeBtn.TextSize = 13
        freezeBtn.Text = "FREEZE 30: OFF"
        freezeBtn.Parent = card
        corner(freezeBtn, 8)

        local stateLabel = Instance.new("TextLabel")
        stateLabel.Name = "FreezeThirtyStatus"
        stateLabel.BackgroundTransparency = 1
        stateLabel.Position = UDim2.fromOffset(257, 102)
        stateLabel.Size = UDim2.fromOffset(595, 38)
        stateLabel.TextColor3 = Color3.fromRGB(77, 84, 103)
        stateLabel.TextXAlignment = Enum.TextXAlignment.Left
        stateLabel.TextSize = 12
        stateLabel.Font = Enum.Font.Gotham
        stateLabel.Text = "Waiting for server..."
        stateLabel.Parent = card

        local detail = Instance.new("TextLabel")
        detail.Position = UDim2.fromOffset(16, 153)
        detail.Size = UDim2.fromOffset(840, 38)
        detail.BackgroundTransparency = 1
        detail.TextWrapped = true
        detail.TextColor3 = Color3.fromRGB(110, 116, 134)
        detail.TextSize = 11
        detail.TextXAlignment = Enum.TextXAlignment.Left
        detail.TextYAlignment = Enum.TextYAlignment.Top
        detail.Text = "ON freezes selected players until OFF; no CarryRequest traffic. Requires the companion server script in ServerScriptService."
        detail.Parent = card

        local serverOn = false
        local busy = false
        local function redraw(frozenCount)
            freezeBtn.Text = serverOn and "FREEZE 30: ON" or "FREEZE 30: OFF"
            freezeBtn.BackgroundColor3 = serverOn and Color3.fromRGB(149, 73, 95) or Color3.fromRGB(40, 44, 55)
            stateLabel.Text = string.format("%s  |  %d of 30 players selected", serverOn and "ACTIVE" or "INACTIVE", frozenCount or 0)
        end
        local eventConn = ownerRemote.OnClientEvent:Connect(function(on, count)
            serverOn = (on == true)
            busy = false
            redraw(count)
        end)
        Gui.Destroying:Connect(function() eventConn:Disconnect() end)
        persistentToggle(freezeBtn, function()
            if busy then return end
            if serverOn then
                busy = true
                ownerRemote:FireServer("set", false, {})
                stateLabel.Text = "Requesting OFF..."
                return
            end
            local targetIds = {}
            for _, other in ipairs(Players:GetPlayers()) do
                if shouldFreezeTarget(other) then
                    targetIds[#targetIds + 1] = other.UserId
                    if #targetIds >= 30 then break end
                end
            end
            if #targetIds == 0 then
                stateLabel.Text = "No eligible targets â add names or ALL to Blacklist above"
                return
            end
            busy = true
            stateLabel.Text = "Requesting server Freeze..."
            ownerRemote:FireServer("set", true, targetIds)
        end)
        ownerRemote:FireServer("sync")
    else
        warn("[VOID HUB OWNER] Freeze 30 server remote not detected. Original V96 GUI is intact; server Freeze 30 is unavailable here.")
    end
end


-- ============================================================================
-- VOID HUB V83 | ABUSE: PLAYER ACTIVITY WATCH (PASSIVE / CLIENT OBSERVATIONS)
-- Shows ALL players, including yourself, with hints of unusual movement,
-- freeze-like character states, and carry-related signals addressed to you.
-- IMPORTANT: Roblox clients cannot read other players' FireServer calls.
-- These are observational flags, NEVER proof of scripting or attribution.
-- No remote is fired and no player is automatically targeted by this monitor.
-- ============================================================================
do
    local page = pages["Abuse"]
    page.CanvasSize = UDim2.fromOffset(0, 580)
    local Replicated = game:GetService("ReplicatedStorage")
    local records = {}
    local rows = {}
    local recentEvents = {}
    local scanElapsed, displayElapsed = 0, 0
    local WATCH_INTERVAL = 0.25
    local DISPLAY_INTERVAL = 0.65

    local function label(parent, text, x, y, w, h, size, color, bold)
        local node = Instance.new("TextLabel")
        node.Size = UDim2.fromOffset(w, h)
        node.Position = UDim2.fromOffset(x, y)
        node.BackgroundTransparency = 1
        node.Text = text
        node.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
        node.TextColor3 = color or Color3.fromRGB(46, 51, 68)
        node.TextSize = size or 12
        node.TextXAlignment = Enum.TextXAlignment.Left
        node.TextYAlignment = Enum.TextYAlignment.Center
        node.TextTruncate = Enum.TextTruncate.AtEnd
        node.Parent = parent
        return node
    end

    local title = label(page, "PLAYER ACTIVITY WATCH", 0, 2, 650, 30, 17, Color3.fromRGB(28, 31, 42), true)
    title.Name = "AbuseHeading"
    local intro = Instance.new("Frame")
    intro.Name = "WatchExplanation"
    intro.Position = UDim2.fromOffset(0, 41)
    intro.Size = UDim2.fromOffset(880, 103)
    intro.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    intro.BorderSizePixel = 0
    corner(intro, 10)
    stroke(intro, Color3.fromRGB(210, 214, 225), 1)
    intro.Parent = page
    local description = label(intro,
        "Watches nearby game effects: sudden movement, freeze-like states and carry signals to YOU. " ..
        "These are clues, not proof of exploit use, and a flagged player may be the VICTIM.",
        14, 11, 850, 46, 12, Color3.fromRGB(75, 81, 100), false)
    description.TextWrapped = true
    description.TextTruncate = Enum.TextTruncate.None
    local countLabel = label(intro, "Players online: 0  |  Monitoring", 14, 63, 660, 25, 13,
        Color3.fromRGB(37, 100, 78), true)
    countLabel.Name = "PlayerCount"

    local clearButton = Instance.new("TextButton")
    clearButton.Name = "ClearAbuseSignals"
    clearButton.Size = UDim2.fromOffset(135, 30)
    clearButton.Position = UDim2.fromOffset(728, 61)
    clearButton.BackgroundColor3 = Color3.fromRGB(232, 234, 243)
    clearButton.Text = "CLEAR ALERTS"
    clearButton.TextColor3 = Color3.fromRGB(49, 54, 69)
    clearButton.TextSize = 12
    clearButton.Font = Enum.Font.GothamBold
    clearButton.Parent = intro
    corner(clearButton, 7)

    label(page, "PLAYER / USERNAME", 14, 156, 330, 21, 12, Color3.fromRGB(105, 112, 130), true)
    label(page, "OBSERVED ACTIVITY", 390, 156, 460, 21, 12, Color3.fromRGB(105, 112, 130), true)

    local logHeading = label(page, "RECENT ACTIVITY SIGNALS", 0, 210, 850, 26, 14,
        Color3.fromRGB(28, 31, 42), true)
    local logCard = Instance.new("Frame")
    logCard.Name = "AbuseRecentEvents"
    logCard.Size = UDim2.fromOffset(880, 155)
    logCard.Position = UDim2.fromOffset(0, 240)
    logCard.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    logCard.BorderSizePixel = 0
    corner(logCard, 10)
    stroke(logCard, Color3.fromRGB(210, 214, 225), 1)
    logCard.Parent = page
    local logText = label(logCard, "No observed activity yet.", 14, 9, 852, 137, 12,
        Color3.fromRGB(80, 86, 103), false)
    logText.Name = "AbuseLogText"
    logText.TextWrapped = true
    logText.TextYAlignment = Enum.TextYAlignment.Top
    logText.TextTruncate = Enum.TextTruncate.None

    local function getRecord(plr)
        local rec = records[plr]
        if not rec then
            rec = { flags = {}, lastNote = {}, carryTimes = {} }
            records[plr] = rec
        end
        return rec
    end

    local function flag(plr, key, status, detail, lifetime, spacing)
        local now = os.clock()
        local rec = getRecord(plr)
        local last = rec.lastNote[key] or -math.huge
        if now - last < (spacing or 5) then return end
        rec.lastNote[key] = now
        rec.flags[key] = { status = status, detail = detail, expires = now + (lifetime or 15) }
        table.insert(recentEvents, 1, { time = now, name = plr.Name, detail = detail })
        while #recentEvents > 8 do table.remove(recentEvents) end
    end

    local function getStatus(rec, now)
        if not rec then return "No alerts", "No unusual signals observed", Color3.fromRGB(74, 123, 97) end
        local checks = {
            { "repeatCarry", Color3.fromRGB(171, 65, 65) },
            { "carry", Color3.fromRGB(174, 115, 46) },
            { "freeze", Color3.fromRGB(174, 115, 46) },
            { "move", Color3.fromRGB(174, 115, 46) },
        }
        for _, item in ipairs(checks) do
            local f = rec.flags[item[1]]
            if f and now < f.expires then return f.status, f.detail, item[2] end
        end
        return "No alerts", "No unusual signals observed", Color3.fromRGB(74, 123, 97)
    end

    local function createRow(plr)
        local row = Instance.new("Frame")
        row.Name = "Activity_" .. tostring(plr.UserId)
        row.Size = UDim2.fromOffset(880, 52)
        row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        row.BorderSizePixel = 0
        corner(row, 8)
        stroke(row, Color3.fromRGB(222, 225, 234), 1)
        row.Parent = page
        local display = label(row, "", 13, 5, 342, 22, 13, Color3.fromRGB(31, 35, 46), true)
        local user = label(row, "", 13, 27, 342, 16, 11, Color3.fromRGB(105, 112, 129), false)
        local activity = label(row, "", 390, 5, 470, 22, 12, Color3.fromRGB(74, 123, 97), true)
        local hint = label(row, "", 390, 26, 470, 18, 11, Color3.fromRGB(105, 112, 129), false)
        rows[plr] = { panel = row, display = display, username = user,
            activity = activity, hint = hint }
        return rows[plr]
    end

    local function draw()
        if not page.Visible then return end
        local now = os.clock()
        local ordered = Players:GetPlayers()
        table.sort(ordered, function(a, b)
            if a == Player then return true end
            if b == Player then return false end
            return a.Name:lower() < b.Name:lower()
        end)
        local seen = {}
        for index, plr in ipairs(ordered) do
            seen[plr] = true
            local row = rows[plr] or createRow(plr)
            row.panel.Position = UDim2.fromOffset(0, 180 + (index - 1) * 57)
            row.display.Text = (plr.DisplayName ~= plr.Name and plr.DisplayName or plr.Name) ..
                (plr == Player and "  (YOU)" or "")
            row.username.Text = "@" .. plr.Name
            local status, detail, color = getStatus(records[plr], now)
            row.activity.Text = status
            row.activity.TextColor3 = color
            row.hint.Text = detail
        end
        for plr, row in pairs(rows) do
            if not seen[plr] then
                row.panel:Destroy()
                rows[plr] = nil
            end
        end
        local signalCount = 0
        for _, rec in pairs(records) do
            for _, f in pairs(rec.flags) do
                if now < f.expires then signalCount += 1; break end
            end
        end
        countLabel.Text = ("Players online: %d  |  Recent signals: %d  |  Monitoring")
            :format(#ordered, signalCount)
        local logY = 180 + #ordered * 57 + 14
        logHeading.Position = UDim2.fromOffset(0, logY)
        logCard.Position = UDim2.fromOffset(0, logY + 30)
        page.CanvasSize = UDim2.fromOffset(0, logY + 199)
        local lines = {}
        for i = 1, math.min(#recentEvents, 6) do
            local ev = recentEvents[i]
            table.insert(lines, ("%ds ago  @%s â %s"):format(
                math.max(0, math.floor(now - ev.time)), ev.name, ev.detail))
        end
        logText.Text = #lines > 0 and table.concat(lines, "\n") or "No observed activity yet."
    end

    local function resetAlerts()
        for _, rec in pairs(records) do
            rec.flags = {}
            rec.lastNote = {}
            rec.carryTimes = {}
        end
        table.clear(recentEvents)
        draw()
    end
    clearButton.Activated:Connect(resetAlerts)

    local function samplePlayer(plr, now)
        local rec = getRecord(plr)
        local character = plr.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if not root or not humanoid or humanoid.Health <= 0 then
            rec.character, rec.root, rec.prevPos, rec.prevTime = nil, nil, nil, nil
            rec.freezeSince = nil
            return
        end
        if rec.character ~= character or rec.root ~= root then
            rec.character, rec.root = character, root
            rec.prevPos, rec.prevTime = root.Position, now
            rec.freezeSince = nil
            return
        end

        if rec.prevPos and rec.prevTime then
            local dt = now - rec.prevTime
            if dt > 0.05 and dt < 1 then
                local jump = (root.Position - rec.prevPos).Magnitude
                -- A large instantaneous move can be a legit class/event teleport.
                -- It is NOT proof of Bring or a specific player using a script.
                if jump >= 65 and jump / dt >= 140 then
                    flag(plr, "move", "Sudden move (possible Bring effect)",
                        ("Large position change: ~%d studs (could be a game teleport)")
                        :format(math.floor(jump + 0.5)), 18, 9)
                end
            end
        end
        rec.prevPos, rec.prevTime = root.Position, now

        local seated = humanoid.Sit or humanoid:GetState() == Enum.HumanoidStateType.Seated
        local constrained = not seated and (root.Anchored or humanoid.PlatformStand
            or humanoid.WalkSpeed <= 0.1)
        if constrained then
            rec.freezeSince = rec.freezeSince or now
            if now - rec.freezeSince >= 0.85 then
                local why = root.Anchored and "anchored root" or
                    (humanoid.PlatformStand and "PlatformStand" or "WalkSpeed near zero")
                flag(plr, "freeze", "Freeze-like effect observed",
                    why .. " (may be normal game behavior)", 16, 10)
            end
        else
            rec.freezeSince = nil
        end
    end

    -- The local client may receive carry-related signals addressed to it.
    -- These can sometimes identify a requester, but do not reveal all remote
    -- activity in the server, and ordinary players also use the carry feature.
    local function registerCarrySignal(sender)
        if typeof(sender) ~= "Instance" or not sender:IsA("Player") or sender == Player then
            return
        end
        local rec = getRecord(sender)
        local now = os.clock()
        local times = rec.carryTimes
        table.insert(times, now)
        for i = #times, 1, -1 do
            if now - times[i] > 5 then table.remove(times, i) end
        end
        if #times >= 6 then
            flag(sender, "repeatCarry", "Repeated carry signals to you",
                ("%d carry-related events in 5s (not proof of scripting)"):format(#times),
                22, 5)
        else
            flag(sender, "carry", "Carry signal to you",
                "Game reported a carry-related interaction (not proof of abuse)", 14, 5)
        end
    end

    local carryRemote = Replicated:FindFirstChild("CarryStarted")
    if carryRemote and carryRemote:IsA("RemoteEvent") then
        bindGlobal(carryRemote.OnClientEvent, function(...)
            local args = table.pack(...)
            for i = 1, args.n do
                local arg = args[i]
                if typeof(arg) == "Instance" and arg:IsA("Player") then
                    registerCarrySignal(arg)
                    break
                end
            end
        end)
    end
    local requestRemote = Replicated:FindFirstChild("SendRequestGui")
    if requestRemote and requestRemote:IsA("RemoteEvent") then
        bindGlobal(requestRemote.OnClientEvent, function(...)
            local args = table.pack(...)
            for i = 1, args.n do
                local arg = args[i]
                if typeof(arg) == "Instance" and arg:IsA("Player") then
                    registerCarrySignal(arg)
                    break
                end
            end
        end)
    end

    bindGlobal(Players.PlayerRemoving, function(plr)
        records[plr] = nil
        if rows[plr] then
            rows[plr].panel:Destroy()
            rows[plr] = nil
        end
    end)
    bindGlobal(RunService.Heartbeat, function(dt)
        scanElapsed += dt
        displayElapsed += dt
        if scanElapsed >= WATCH_INTERVAL then
            scanElapsed = 0
            local now = os.clock()
            for _, plr in ipairs(Players:GetPlayers()) do samplePlayer(plr, now) end
        end
        if displayElapsed >= DISPLAY_INTERVAL then
            displayElapsed = 0
            draw()
        end
    end)
    draw()
end
-- END VOID HUB V83 PLAYER ACTIVITY WATCH

-- =====================================================================
-- ATTACK: NO HIT ANIMS (V131) - INCLUDE G-KEY ACTION ANIMATIONS
-- Hide your own punch / strike animation while the game still handles attacks.
-- This does not alter damage, hit registration, physics, or other players.
-- =====================================================================
do
    local page = pages["Attack"]
    if page then
        local card = makeFeatureCard(page, "No Hit Anims", 1490)
        card.Name = "AttackNoHitAnims"
        card.Size = UDim2.fromOffset(880, 116)
        page.CanvasSize = UDim2.fromOffset(0, math.max(page.CanvasSize.Y.Offset, 1625))

        local toggle = Instance.new("TextButton")
        toggle.Name = "NoHitAnimsToggle"
        toggle.Position = UDim2.fromOffset(16, 42)
        toggle.Size = UDim2.fromOffset(214, 36)
        toggle.Font = Enum.Font.GothamBold
        toggle.TextSize = 12
        toggle.AutoButtonColor = false
        toggle.Parent = card
        corner(toggle, 8)

        local status = Instance.new("TextLabel")
        status.Name = "NoHitAnimsStatus"
        status.BackgroundTransparency = 1
        status.Position = UDim2.fromOffset(248, 41)
        status.Size = UDim2.fromOffset(614, 55)
        status.TextColor3 = Color3.fromRGB(65, 72, 90)
        status.TextSize = 12
        status.Font = Enum.Font.Gotham
        status.TextWrapped = true
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextYAlignment = Enum.TextYAlignment.Center
        status.Parent = card

        local enabled = false
        local alive = true
        local stoppedCount = 0
        local attachGeneration = 0
        local characterConnections = {}
        local attackWindowUntil = 0
        local gActionWindowUntil = 0
        -- Track short reaction windows after damage, without disabling movement.
        local damageReactionUntil = 0

        local function redraw()
            if not alive or not Gui.Parent then return end
            toggle.Text = enabled and "NO HIT ANIMS: ON" or "NO HIT ANIMS: OFF"
            animateToggle(toggle, enabled)
            if enabled then
                status.Text = ("ON. Hidden %d local attack / hit-reaction animations. " ..
                    "Local animation only; damage and physics still apply."):format(stoppedCount)
            else
                status.Text = "OFF. Normal attack animations on your character."
            end
        end

        local protectedWords = {"walk", "run", "idle", "jump", "fall", "swim", "climb",
            "block", "guard", "parry", "equip", "emote", "dance", "carry", "grab",
            "hurt", "flinch", "stagger", "stun", "knock", "ragdoll", "damage", "sit"}
        local attackWords = {"punch", "jab", "strike", "swing", "uppercut", "hook",
            "fist", "attack", "combo", "slap", "smack", "melee", "combat",
            "kick", "leftclick", "lightattack", "heavyattack", "hitbox"}

        local function attackNameMatches(name)
            if name == "" then return false end
            for _, word in ipairs(protectedWords) do
                if name:find(word, 1, true) then return false end
            end
            for _, word in ipairs(attackWords) do
                if name:find(word, 1, true) then return true end
            end
            return name == "m1" or name == "m2" or name:match("^m1%d+$") ~= nil
                or name:match("^hit%d*$") ~= nil
        end

        local function isAttackTrack(track)
            local names = {}
            pcall(function()
                names[#names + 1] = tostring(track.Name or "")
                if track.Animation then
                    names[#names + 1] = tostring(track.Animation.Name or "")
                end
            end)
            for _, raw in ipairs(names) do
                local cleaned = raw:lower():gsub("[%s_%-%.]", "")
                if attackNameMatches(cleaned) then return true end
            end
            -- G can play an unnamed or "grab"-named action animation.
            -- Catch it in a brief G-key window without affecting locomotion.
            if os.clock() <= gActionWindowUntil then
                local ok, priority = pcall(function() return track.Priority end)
                if ok and (priority == Enum.AnimationPriority.Action
                    or priority == Enum.AnimationPriority.Action2
                    or priority == Enum.AnimationPriority.Action3
                    or priority == Enum.AnimationPriority.Action4) then
                    for _, raw in ipairs(names) do
                        local cleaned = raw:lower():gsub("[%s_%-%.]", "")
                        for _, word in ipairs({"walk", "run", "idle", "jump", "fall",
                            "swim", "climb", "sit"}) do
                            if cleaned:find(word, 1, true) then return false end
                        end
                    end
                    return true
                end
            end
            -- Some games name every animation simply 'Animation'. In that case,
            -- only treat action-priority tracks started immediately after an
            -- actual attack click as likely outgoing hit animations.
            if os.clock() <= attackWindowUntil then
                local ok, priority = pcall(function() return track.Priority end)
                if ok and (priority == Enum.AnimationPriority.Action
                    or priority == Enum.AnimationPriority.Action2
                    or priority == Enum.AnimationPriority.Action3
                    or priority == Enum.AnimationPriority.Action4) then
                    for _, raw in ipairs(names) do
                        local cleaned = raw:lower():gsub("[%s_%-%.]", "")
                        for _, word in ipairs(protectedWords) do
                            if cleaned:find(word, 1, true) then return false end
                        end
                    end
                    return true
                end
            end
            return false
        end

        local reactionWords = {"hurt", "flinch", "stagger", "stun", "knock",
            "damage", "gethit", "hitreact", "hitstun", "hitreceived", "impactreact"}
        local reactionProtected = {"walk", "run", "idle", "jump", "fall",
            "swim", "climb", "sit", "block", "guard", "parry", "equip", "emote"}
        local function isReactionTrack(track)
            local names = {}
            pcall(function()
                names[#names + 1] = tostring(track.Name or ""):lower():gsub("[%s_%-%.]", "")
                if track.Animation then
                    names[#names + 1] = tostring(track.Animation.Name or ""):lower():gsub("[%s_%-%.]", "")
                end
            end)
            for _, name in ipairs(names) do
                for _, word in ipairs(reactionWords) do
                    if name:find(word, 1, true) then return true end
                end
            end
            -- When the game uses unnamed animations, use the damage window
            -- and Action priority to distinguish hit reactions from movement.
            if os.clock() > damageReactionUntil
                or os.clock() <= attackWindowUntil
                or os.clock() <= gActionWindowUntil then return false end
            local ok, priority = pcall(function() return track.Priority end)
            if not ok or (priority ~= Enum.AnimationPriority.Action
                and priority ~= Enum.AnimationPriority.Action2
                and priority ~= Enum.AnimationPriority.Action3
                and priority ~= Enum.AnimationPriority.Action4) then return false end
            for _, name in ipairs(names) do
                for _, word in ipairs(reactionProtected) do
                    if name:find(word, 1, true) then return false end
                end
            end
            return true
        end
        local function inspectTrack(track)
            if not (enabled and alive)
                or not (isAttackTrack(track) or isReactionTrack(track)) then return end
            local success = pcall(function() track:Stop(0) end)
            if success then
                stoppedCount += 1
                redraw()
            end
        end

        local function inspectPlayingTracks()
            local character = Player.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
            if not animator then return end
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                inspectTrack(track)
            end
        end

        local function disconnectCharacter()
            for _, conn in ipairs(characterConnections) do
                conn:Disconnect()
            end
            table.clear(characterConnections)
        end

        local function attachCharacter(character)
            attachGeneration += 1
            local generation = attachGeneration
            disconnectCharacter()
            task.spawn(function()
                local humanoid = character:FindFirstChildOfClass("Humanoid")
                    or character:WaitForChild("Humanoid", 8)
                if not humanoid or not alive or Player.Character ~= character
                    or generation ~= attachGeneration then return end
                local animator = humanoid:FindFirstChildOfClass("Animator")
                    or humanoid:WaitForChild("Animator", 8)
                if not animator or not alive or Player.Character ~= character
                    or generation ~= attachGeneration then return end
                table.insert(characterConnections, animator.AnimationPlayed:Connect(inspectTrack))
                -- React immediately when HP falls, including animations already playing.
                local lastHealth = humanoid.Health
                table.insert(characterConnections, humanoid.HealthChanged:Connect(function(newHealth)
                    if newHealth < lastHealth - 0.01 and enabled then
                        damageReactionUntil = os.clock() + 0.5
                        inspectPlayingTracks()
                        task.defer(inspectPlayingTracks)
                    end
                    lastHealth = newHealth
                end))
                local nextReactionScan = 0
                table.insert(characterConnections, RunService.Heartbeat:Connect(function()
                    local now = os.clock()
                    if enabled and alive and now <= damageReactionUntil
                        and now >= nextReactionScan then
                        nextReactionScan = now + 0.05
                        inspectPlayingTracks()
                    end
                end))
                if enabled then inspectPlayingTracks() end
            end)
        end

        -- Support unnamed punch tracks after click and action tracks from G.
        bindGlobal(UIS.InputBegan, function(inputObject, gameProcessed)
            if not alive or not enabled or UIS:GetFocusedTextBox() then return end
            if inputObject.KeyCode == Enum.KeyCode.G then
                -- Capture G even when the game handles the key itself.
                gActionWindowUntil = os.clock() + 0.75
                task.defer(inspectPlayingTracks)
                task.delay(0.08, function()
                    if alive and enabled and os.clock() <= gActionWindowUntil then
                        inspectPlayingTracks()
                    end
                end)
                task.delay(0.25, function()
                    if alive and enabled and os.clock() <= gActionWindowUntil then
                        inspectPlayingTracks()
                    end
                end)
            elseif not gameProcessed and (inputObject.UserInputType == Enum.UserInputType.MouseButton1
                or inputObject.KeyCode == Enum.KeyCode.ButtonR2) then
                attackWindowUntil = os.clock() + 0.35
                task.defer(inspectPlayingTracks)
            end
        end)

        persistentToggle(toggle, function()
            enabled = not enabled
            attackWindowUntil = 0
            gActionWindowUntil = 0
            damageReactionUntil = 0
            if enabled then inspectPlayingTracks() end
            redraw()
        end)

        bindGlobal(Player.CharacterAdded, attachCharacter)
        if Player.Character then attachCharacter(Player.Character) end
        Gui.Destroying:Connect(function()
            enabled, alive = false, false
            attachGeneration += 1
            disconnectCharacter()
        end)
        redraw()
    end
end


-- =====================================================================
-- Shared release hook: never let Player Hitboxes capture a temporary
-- PC Aura-sized HumanoidRootPart as its permanent "original".
local releasePCAuraHitbox = nil

-- ATTACK: PLAYER HITBOXES (V135) - invisible size-only hitbox test.
-- Uses existing VOID HUB Attack tab; no separate GUI and no blue visuals.
-- Only changes local player-root size and transparency; does not touch material/color.
-- Server-side hit detection/range checks are not bypassed.
-- =====================================================================
do
    local page = pages["Attack"]
    if page then
        local card = makeFeatureCard(page, "Player Hitboxes", 1625)
        card.Name = "AttackPlayerHitboxes"
        card.Size = UDim2.fromOffset(880, 226)
        page.CanvasSize = UDim2.fromOffset(0, math.max(page.CanvasSize.Y.Offset, 1890))

        local function makeLabel(caption, x, y, width)
            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Position = UDim2.fromOffset(x, y)
            label.Size = UDim2.fromOffset(width, 20)
            label.Font = Enum.Font.Gotham
            label.TextSize = 12
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextColor3 = Color3.fromRGB(65, 72, 90)
            label.Text = caption
            label.Parent = card
        end
        local function makeBox(name, value, x, y, width)
            local box = Instance.new("TextBox")
            box.Name = name
            box.Position = UDim2.fromOffset(x, y)
            box.Size = UDim2.fromOffset(width, 34)
            box.ClearTextOnFocus = false
            box.BackgroundColor3 = Color3.fromRGB(239, 243, 250)
            box.TextColor3 = Color3.fromRGB(25, 30, 43)
            box.Font = Enum.Font.Gotham
            box.TextSize = 13
            box.Text = value
            corner(box, 7)
            box.Parent = card
            return box
        end
        makeLabel("Hitbox size (2â100 studs)", 16, 40, 382)
        local sizeBox = makeBox("PlayerHitboxSize", "100", 16, 63, 382)
        makeLabel("Auto refresh (seconds)", 428, 40, 434)
        local refreshBox = makeBox("PlayerHitboxRefresh", "0.15", 428, 63, 434)

        local toggle = Instance.new("TextButton")
        toggle.Name = "PlayerHitboxToggle"
        toggle.Position = UDim2.fromOffset(16, 113)
        toggle.Size = UDim2.fromOffset(210, 36)
        toggle.Font = Enum.Font.GothamBold
        toggle.TextSize = 12
        toggle.AutoButtonColor = false
        toggle.Parent = card
        corner(toggle, 8)

        local status = Instance.new("TextLabel")
        status.Name = "PlayerHitboxStatus"
        status.BackgroundTransparency = 1
        status.Position = UDim2.fromOffset(245, 110)
        status.Size = UDim2.fromOffset(616, 51)
        status.TextColor3 = Color3.fromRGB(65, 72, 90)
        status.TextSize = 12
        status.Font = Enum.Font.Gotham
        status.TextWrapped = true
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextYAlignment = Enum.TextYAlignment.Center
        status.Parent = card

        local note = Instance.new("TextLabel")
        note.Name = "PlayerHitboxNote"
        note.BackgroundTransparency = 1
        note.Position = UDim2.fromOffset(16, 165)
        note.Size = UDim2.fromOffset(846, 54)
        note.TextColor3 = Color3.fromRGB(95, 100, 112)
        note.Font = Enum.Font.Gotham
        note.TextSize = 11
        note.TextWrapped = true
        note.TextXAlignment = Enum.TextXAlignment.Left
        note.TextYAlignment = Enum.TextYAlignment.Top
        note.Text = "No blue outline, glow, or ForceField. Hitboxes are fully invisible. Existing VOID HUB whitelist stays protected. Changes are local and may not affect server-validated punch range. OFF restores original parts."
        note.Parent = card

        local Hitbox = {
            Enabled = false,
            Size = 100,
            RefreshInterval = 0.15,
            Originals = {},
        }
        local alive = true
        local refreshToken = 0
        local modifiedCount = 0
        local message = "OFF. No player hitboxes are modified."

        local function render()
            if not alive or not Gui.Parent then return end
            toggle.Text = Hitbox.Enabled and "HITBOXES: ON" or "HITBOXES: OFF"
            animateToggle(toggle, Hitbox.Enabled)
            status.Text = message
        end

        local function saveOriginal(root)
            if not Hitbox.Originals[root] then
                Hitbox.Originals[root] = {
                    Size = root.Size,
                    Transparency = root.Transparency,
                    Color = root.Color,
                    Material = root.Material,
                }
            end
        end

        local function restore(root)
            local original = Hitbox.Originals[root]
            if not original then return end
            pcall(function()
                if root and root.Parent then
                    root.Size = original.Size
                    root.Transparency = original.Transparency
                    root.Color = original.Color
                    root.Material = original.Material
                end
            end)
            Hitbox.Originals[root] = nil
        end

        local function restoreAll()
            for root in pairs(Hitbox.Originals) do
                restore(root)
            end
            modifiedCount = 0
        end

        -- Reuses the existing VOID HUB whitelist instead of the friend's
        -- unspecified Whitelist.IsWhitelisted / proxy functions.
        local function updateCharacter(other)
            if other == Player then return end
            local character = other.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            if not Hitbox.Enabled or inPlayerList(State.Whitelist, other) then
                restore(root)
                return
            end
            saveOriginal(root)
            -- Keep the root completely hidden, without blue boxes or ForceField.
            -- Avoid repeatedly assigning identical properties every refresh.
            local desiredSize = Vector3.new(Hitbox.Size, Hitbox.Size, Hitbox.Size)
            if root.Size ~= desiredSize then root.Size = desiredSize end
            if root.Transparency ~= 1 then root.Transparency = 1 end
        end

        local function updateAll()
            if not alive then return end
            -- Clear old roots after respawn or leaving the game.
            for root in pairs(Hitbox.Originals) do
                if not root or not root:IsDescendantOf(workspace) then
                    Hitbox.Originals[root] = nil
                end
            end
            for _, other in ipairs(Players:GetPlayers()) do
                local ok, err = pcall(updateCharacter, other)
                if not ok then
                    warn("[VOID HUB HITBOX] Update failed for " .. other.Name .. ": " .. tostring(err))
                end
            end
            local count = 0
            for _ in pairs(Hitbox.Originals) do count += 1 end
            modifiedCount = count
            if Hitbox.Enabled then
                message = ("ON. %d invisible hitbox(es) sized locally to %.1f studs. Server may ignore increased range.")
                    :format(modifiedCount, Hitbox.Size)
            end
            render()
        end

        local function readSettings()
            Hitbox.Size = math.clamp(tonumber(sizeBox.Text) or Hitbox.Size, 2, 100)
            Hitbox.RefreshInterval = math.clamp(tonumber(refreshBox.Text) or Hitbox.RefreshInterval, 0.05, 5)
            sizeBox.Text = tostring(Hitbox.Size)
            refreshBox.Text = tostring(Hitbox.RefreshInterval)
        end

        local function setEnabled(value)
            if value and releasePCAuraHitbox then
                releasePCAuraHitbox()
            end
            Hitbox.Enabled = value
            refreshToken += 1
            local thisToken = refreshToken
            if value then
                readSettings()
                updateAll()
                task.spawn(function()
                    while alive and Gui.Parent and Hitbox.Enabled and refreshToken == thisToken do
                        task.wait(Hitbox.RefreshInterval)
                        if alive and Gui.Parent and Hitbox.Enabled and refreshToken == thisToken then
                            updateAll()
                        end
                    end
                end)
            else
                restoreAll()
                message = "OFF. Original player hitboxes and visibility restored."
            end
            render()
        end

        persistentToggle(toggle, function()
            setEnabled(not Hitbox.Enabled)
        end)
        for _, box in ipairs({sizeBox, refreshBox}) do
            box.FocusLost:Connect(function()
                readSettings()
                if Hitbox.Enabled then updateAll() end
            end)
        end
        bindGlobal(Players.PlayerRemoving, function(other)
            local character = other.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            if root then restore(root) end
        end)
        Gui.Destroying:Connect(function()
            Hitbox.Enabled = false
            refreshToken += 1
            restoreAll()
            alive = false
        end)
        render()
    end
end


-- ============================================================================
-- V136 / CLEAN LAYOUT AND NAVIGATION
-- Presentation only. Feature callbacks, values, remotes, state and cleanup stay
-- in the original sections above. Reorder existing cards after construction.
-- ============================================================================
do
    local ink = Color3.fromRGB(35, 45, 65)
    local muted = Color3.fromRGB(98, 108, 130)
    local edge = Color3.fromRGB(219, 225, 237)
    local surface = Color3.fromRGB(255, 255, 255)
    local cloud = Color3.fromRGB(235, 240, 250)
    local highlight = Color3.fromRGB(73, 111, 174)

    local headerDivider = Instance.new("Frame")
    headerDivider.Name = "TopDivider"
    headerDivider.Position = UDim2.fromOffset(20, 48)
    headerDivider.Size = UDim2.fromOffset(900, 1)
    headerDivider.BorderSizePixel = 0
    headerDivider.BackgroundColor3 = edge
    headerDivider.Parent = Main

    local version = Instance.new("TextLabel")
    version.Name = "Edition"
    version.BackgroundTransparency = 1
    version.Position = UDim2.fromOffset(196, 14)
    version.Size = UDim2.fromOffset(198, 25)
    version.Font = Enum.Font.GothamMedium
    version.Text = "V1"
    version.TextSize = 11
    version.TextColor3 = muted
    version.TextXAlignment = Enum.TextXAlignment.Left
    version.Parent = Main

    local close = Instance.new("TextButton")
    close.Name = "HidePanel"
    close.Size = UDim2.fromOffset(32, 30)
    close.Position = UDim2.fromOffset(816, 12)
    close.BackgroundColor3 = cloud
    close.Text = "X"
    close.Font = Enum.Font.GothamBold
    close.TextSize = 13
    close.TextColor3 = ink
    close.ZIndex = 20
    close.Parent = Main
    corner(close, 8)
    close.Activated:Connect(function()
        setPanel(false) -- The V launcher remains visible to reopen the hub.
    end)

    -- Harmonize the visual language without replacing any controls.
    for _, object in ipairs(Main:GetDescendants()) do
        if object:IsA("ScrollingFrame") then
            object.ScrollBarImageColor3 = Color3.fromRGB(152, 165, 188)
            object.ScrollBarThickness = math.max(5, object.ScrollBarThickness)
        elseif object:IsA("TextBox") then
            object.PlaceholderColor3 = muted
            if object.BackgroundTransparency < 1 then
                object.BackgroundColor3 = Color3.fromRGB(243, 246, 252)
            end
        elseif object:IsA("Frame") and object.Parent == Content or
            (object:IsA("Frame") and object.Parent and object.Parent:IsA("ScrollingFrame") and object.Name ~= "tracerCanvas") then
            if object.BackgroundTransparency < 1 then object.BackgroundColor3 = surface end
        end
    end

    local cardTitles = {
        TPWalkCard = "TP Walk",
        Follow4StudsBehindCard = "Follow  |  4 studs behind",
        NoSlowCard = "No Slow",
        WalkSpeedCard = "Walk Speed",
        AnnouncementCard = "Announcement",
        HealthBarsCard = "Health Bars",
        AntiVoidCard = "Anti Void",
        DeathTPCard = "Death TP",
    }
    local function move(page, name, x, y)
        local item = page:FindFirstChild(name)
        if not item and cardTitles[name] then
            for _, candidate in ipairs(page:GetChildren()) do
                if candidate:IsA("Frame") then
                    local titleLabel = candidate:FindFirstChildOfClass("TextLabel")
                    if titleLabel and titleLabel.Text == cardTitles[name] then
                        item = candidate
                        break
                    end
                end
            end
        end
        if item and item:IsA("GuiObject") then
            item.Position = UDim2.fromOffset(x, y)
        end
        return item
    end
    local function section(page, text, y)
        local t = Instance.new("TextLabel")
        t.Name = "Section_" .. text:gsub("[^%w]+", "_")
        t.BackgroundTransparency = 1
        t.Position = UDim2.fromOffset(2, y)
        t.Size = UDim2.fromOffset(860, 26)
        t.Font = Enum.Font.GothamBold
        t.Text = text
        t.TextSize = 12
        t.TextColor3 = highlight
        t.TextXAlignment = Enum.TextXAlignment.Left
        t.Parent = page
        local line = Instance.new("Frame")
        line.Name = "SectionDivider"
        line.BackgroundColor3 = edge
        line.BorderSizePixel = 0
        line.Position = UDim2.fromOffset(2, y + 29)
        line.Size = UDim2.fromOffset(876, 1)
        line.Parent = page
        return t
    end
    local function extraInfo(page, message, x, y, w, h)
        local card = Instance.new("Frame")
        card.Name = "HelpInfo"
        card.Position = UDim2.fromOffset(x, y)
        card.Size = UDim2.fromOffset(w, h)
        card.BorderSizePixel = 0
        card.BackgroundColor3 = cloud
        card.Parent = page
        corner(card, 10)
        local caption = Instance.new("TextLabel")
        caption.BackgroundTransparency = 1
        caption.Position = UDim2.fromOffset(16, 12)
        caption.Size = UDim2.new(1, -32, 1, -24)
        caption.Text = message
        caption.TextWrapped = true
        caption.Font = Enum.Font.Gotham
        caption.TextSize = 12
        caption.TextColor3 = muted
        caption.TextXAlignment = Enum.TextXAlignment.Left
        caption.TextYAlignment = Enum.TextYAlignment.Center
        caption.Parent = card
    end

    -- DEFENSE: protection cards arranged from urgent recovery to auxiliary tools.
    DefenseHeading.Text = "PROTECTION & RECOVERY   |   Enable only the tools you need"
    DefenseHeading.TextColor3 = ink
    DefenseHeading.TextSize = 13
    move(DefensePage, "DefenseAntiGrab", 0, 38)
    move(DefensePage, "DefenseAntiRagdoll", 450, 38)
    move(DefensePage, "AntiVoidCard", 0, 260) -- fallback for older naming
    move(DefensePage, "DefenseAntiVoid", 0, 260)
    move(DefensePage, "DeathTPCard", 450, 260)
    DefensePage.CanvasSize = UDim2.fromOffset(0, 831)

    -- ATTACK: short jumps and ordered sections; existing controls are reused.
    local attack = pages["Attack"]
    local jumpBar = Instance.new("Frame")
    jumpBar.Name = "AttackQuickNavigation"
    jumpBar.Position = UDim2.fromOffset(0, 0)
    jumpBar.Size = UDim2.fromOffset(880, 58)
    jumpBar.BackgroundColor3 = cloud
    jumpBar.BorderSizePixel = 0
    jumpBar.Parent = attack
    corner(jumpBar, 10)
    local jumps = {
        {"HITBOX", 75}, {"PLAYER LISTS", 662}, {"CARRY", 963}, {"FREEZE", 1235}
    }
    for i, jump in ipairs(jumps) do
        local btn = Instance.new("TextButton")
        btn.Name = "Jump_" .. i
        btn.Size = UDim2.fromOffset(199, 38)
        btn.Position = UDim2.fromOffset(14 + (i - 1) * 218, 10)
        btn.BackgroundColor3 = surface
        btn.Text = jump[1]
        btn.TextColor3 = ink
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamBold
        btn.Parent = jumpBar
        corner(btn, 8)
        btn.Activated:Connect(function()
            attack.CanvasPosition = Vector2.new(0, jump[2])
        end)
    end
    section(attack, "01    HITBOXES & ANIMATIONS", 72)
    move(attack, "AttackPlayerHitboxes", 0, 109)
    -- The legacy No Hit Anims card is named from its original title.
    move(attack, "AttackNoHitAnims", 0, 346)
    section(attack, "02    PLAYER LISTS  /  TARGET FILTERING", 478)
    move(attack, "PlayerListsCombined", 0, 514)
    move(attack, "SharedListInfo", 4, 705)
    section(attack, "03    BRING  /  GYMBAN", 779)
    move(attack, "AttackCarryControl", 0, 816)
    section(attack, "04    FREEZE  /  REQUEST MANAGEMENT", 1051)

    local legacyDecline = attack:FindFirstChild("OriginalDecline")
    local legacyAccept = attack:FindFirstChild("OriginalAccept")
    local freezeOwner = attack:FindFirstChild("OwnerFreeze30Card")
    local lastBottom = 1098
    if legacyDecline then
        move(attack, "OriginalDecline", 0, 1092)
        move(attack, "OriginalAccept", 450, 1092)
        move(attack, "OriginalDeclineRequests", 0, 1362)
        move(attack, "OriginalSpamCarry", 450, 1362)
        move(attack, "OriginalStats", 0, 1535)
        move(attack, "Freeze100Monitor", 0, 1739)
        -- Hide the outdated duplicate heading; section 04 provides the heading.
        for _, child in ipairs(attack:GetChildren()) do
            if child:IsA("TextLabel") and child.Text:find("FREEZE / CARRY TOOLS", 1, true) then
                child.Visible = false
            elseif child:IsA("TextLabel") and child.Text:find("FREEZE uses the combined lists above", 1, true) then
                child.Position = UDim2.fromOffset(5, 1655)
            end
        end
        lastBottom = 2048
    end
    if freezeOwner then
        freezeOwner.Position = UDim2.fromOffset(0, lastBottom + 17)
        lastBottom = lastBottom + 240
    end
    if not legacyDecline and not freezeOwner then
        extraInfo(attack, "Freeze features are shown here when their supported game services are available.", 0, 1092, 880, 66)
        lastBottom = 1180
    end
    attack.CanvasSize = UDim2.fromOffset(0, lastBottom + 52)

    -- MOVEMENT: travel and follow, orbit, speed, then communication.
    local movement = pages["Movement"]
    section(movement, "01    TELEPORT MOVEMENT & FOLLOW", 2)
    move(movement, "TPWalkCard", 0, 39)
    move(movement, "Follow4StudsBehindCard", 538, 39)
    section(movement, "02    ORBITAL PLAYER", 290)
    move(movement, "MovementOrbitalPlayer", 0, 328)
    section(movement, "03    MOVEMENT SPEED", 543)
    move(movement, "NoSlowCard", 0, 581)
    move(movement, "WalkSpeedCard", 538, 581)
    section(movement, "04    ANNOUNCEMENTS", 781)
    move(movement, "AnnouncementCard", 0, 819)
    movement.CanvasSize = UDim2.fromOffset(0, 1035)

    -- VISUAL: tidy two-column overlay controls with a non-functional help panel.
    local visual = pages["Visual"]
    section(visual, "OVERLAYS  /  KEYBINDS", 0)
    if espCard then espCard.Position = UDim2.fromOffset(0, 39) end
    if tracersCard then tracersCard.Position = UDim2.fromOffset(0, 149) end
    move(visual, "HealthBarsCard", 450, 39)
    extraInfo(visual,
        "ESP highlights players. Tracers draw screen-space lines. Health Bars show replicated HP. Configure keybinds beside the ESP and Tracers toggles.",
        450, 198, 430, 123)
    visual.CanvasSize = UDim2.fromOffset(0, 384)

    -- MONITOR is a neutral tab name for the same original passive observations.
    local monitor = pages["Abuse"]
    local monitorTitle = monitor:FindFirstChild("AbuseHeading")
    if monitorTitle then monitorTitle.Text = "PLAYER ACTIVITY MONITOR" end

    -- Keep all primary feature panels styled consistently.
    for _, page in pairs(pages) do
        for _, element in ipairs(page:GetChildren()) do
            if element:IsA("Frame") and element.BackgroundTransparency < 1 and
                element.Name ~= "SectionDivider" and element.Name ~= "AttackQuickNavigation" and element.Name ~= "HelpInfo" then
                element.BackgroundColor3 = surface
                local outline = element:FindFirstChildOfClass("UIStroke")
                if outline then outline.Color = edge end
                local rounded = element:FindFirstChildOfClass("UICorner")
                if rounded then rounded.CornerRadius = UDim.new(0, 12) end
            end
        end
    end
end


-- ============================================================================
-- ATTACK: KILL AURA (360 SCAN / OPTIONAL PC AURA / NO AVATAR TURN)
-- PC mode integrates friend's target-only enlarged invisible hitbox and
-- center-screen VirtualInputManager click. AUTO/VIM/LEGACY modes remain.
-- Unlike client-only camera-ray aim, PC mode does not move the camera.
-- Hitbox resizing is local; server hit validation still applies.
-- ============================================================================
do
    local page = pages["Attack"]
    if page then
        local card = makeFeatureCard(page, "KILL AURA", 476)
        card.Name = "AttackKillAuraTest" -- preserve existing card identity and position
        card.Size = UDim2.fromOffset(880, 148)

        local function makeLabel(text, x, y, w)
            local label = Instance.new("TextLabel")
            label.BackgroundTransparency = 1
            label.Position = UDim2.fromOffset(x, y)
            label.Size = UDim2.fromOffset(w, 20)
            label.Font = Enum.Font.Gotham
            label.TextSize = 12
            label.TextColor3 = Color3.fromRGB(75, 85, 101)
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.Text = text
            label.Parent = card
        end
        local function makeBox(name, value, x, w)
            local b = Instance.new("TextBox")
            b.Name = name
            b.Position = UDim2.fromOffset(x, 55)
            b.Size = UDim2.fromOffset(w, 34)
            b.BackgroundColor3 = Color3.fromRGB(243, 246, 252)
            b.TextColor3 = Color3.fromRGB(30, 36, 48)
            b.Font = Enum.Font.Gotham
            b.TextSize = 13
            b.Text = value
            b.ClearTextOnFocus = false
            b.Parent = card
            corner(b, 8)
            return b
        end

        local toggle = Instance.new("TextButton")
        toggle.Name = "KillAuraToggle"
        toggle.Position = UDim2.fromOffset(16, 53)
        toggle.Size = UDim2.fromOffset(214, 37)
        toggle.Font = Enum.Font.GothamBold
        toggle.TextSize = 12
        toggle.AutoButtonColor = false
        toggle.Parent = card
        corner(toggle, 8)

        makeLabel("Attack range (3-15 studs)", 252, 33, 190)
        makeLabel("Click speed (1-15 / sec)", 453, 33, 190)
        local rangeBox = makeBox("KillAuraRange", "15", 252, 172)
        -- Keep the existing internal field name for Auto-Save compatibility.
        local intervalBox = makeBox("KillAuraInterval", "9", 453, 172)
        local status = Instance.new("TextLabel")
        status.Name = "KillAuraStatus"
        status.Position = UDim2.fromOffset(17, 101)
        status.Size = UDim2.fromOffset(845, 43)
        status.BackgroundTransparency = 1
        status.TextColor3 = Color3.fromRGB(65, 72, 90)
        status.TextSize = 12
        status.Font = Enum.Font.Gotham
        status.TextWrapped = true
        status.TextXAlignment = Enum.TextXAlignment.Left
        status.TextYAlignment = Enum.TextYAlignment.Top
        status.Parent = card

        local enabled, alive, clicking = false, true, false
        local radius, hitSpeed = 15, 9
        local scannedAt, nextClickAt = 0, 0
        local clicks, lastClickStatusAt = 0, -math.huge
        -- Keep the existing PC Aura method active without extra UI controls.
        local inputMode = "PC"
        local pcHitboxSize = 25
        local pcTargetRoot, pcOriginal = nil, nil
        local observedClicks, lastObservedClick = 0, -math.huge
        local vim = nil
        pcall(function() vim = game:GetService("VirtualInputManager") end)

        local function setStatus(message)
            if alive and Gui.Parent and status.Text ~= message then
                status.Text = message
            end
        end
        local function render()
            if not alive or not Gui.Parent then return end
            toggle.Text = enabled and "KILL AURA: ON" or "KILL AURA: OFF"
            animateToggle(toggle, enabled)
        end
        local function readSettings()
            local requestedRange = tonumber(rangeBox.Text)
            if requestedRange and requestedRange == requestedRange
                and requestedRange ~= math.huge and requestedRange ~= -math.huge then
                radius = math.clamp(math.floor(requestedRange + 0.5), 3, 15)
            end
            local requestedSpeed = tonumber(intervalBox.Text)
            if requestedSpeed and requestedSpeed == requestedSpeed
                and requestedSpeed ~= math.huge and requestedSpeed ~= -math.huge then
                -- Convert saved old click-interval values like 0.12 s to clicks/s.
                if requestedSpeed > 0 and requestedSpeed <= 0.50 then
                    requestedSpeed = 1 / requestedSpeed
                end
                hitSpeed = math.clamp(math.floor(requestedSpeed * 10 + 0.5) / 10, 1, 15)
            end
            rangeBox.Text = tostring(radius)
            intervalBox.Text = tostring(hitSpeed)
        end

        local function playerHitboxesActive()
            local another = page:FindFirstChild("AttackPlayerHitboxes")
            local button = another and another:FindFirstChild("PlayerHitboxToggle")
            return button and button:IsA("TextButton") and button.Text == "HITBOXES: ON"
        end

        local function restorePCHitbox()
            local root = pcTargetRoot
            local original = pcOriginal
            pcTargetRoot, pcOriginal = nil, nil
            if not root or not original or not root.Parent then return end
            pcall(function()
                root.Size = original.Size
                root.Transparency = original.Transparency
                root.CanCollide = original.CanCollide
                root.Shape = original.Shape
            end)
        end
        -- Called before enabling the separate global Player Hitboxes feature.
        releasePCAuraHitbox = restorePCHitbox

        local function updatePCHitbox(target)
            if not enabled or inputMode ~= "PC" or not target or not target.root
                or not target.root.Parent or playerHitboxesActive() then
                restorePCHitbox()
                return false
            end
            local root = target.root
            if root ~= pcTargetRoot then
                restorePCHitbox()
                pcTargetRoot = root
                pcOriginal = {
                    Size = root.Size,
                    Transparency = root.Transparency,
                    CanCollide = root.CanCollide,
                    Shape = root.Shape,
                }
            end
            local desired = Vector3.new(pcHitboxSize, pcHitboxSize, pcHitboxSize)
            pcall(function()
                -- Invisibility and geometry changes are client-local; no
                -- colored Neon visuals or server-side damage are injected.
                if root.Size ~= desired then root.Size = desired end
                if root.Transparency ~= 1 then root.Transparency = 1 end
                if root.CanCollide then root.CanCollide = false end
                if root.Shape ~= Enum.PartType.Ball then root.Shape = Enum.PartType.Ball end
            end)
            return true
        end

        local function findNextTarget()
            local char = Player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 or hum.PlatformStand or DeathTPIsEscaping then
                return nil
            end
            local eligible = {}
            for _, other in ipairs(Players:GetPlayers()) do
                -- Kill Aura targets ALL nearby players except Whitelist.
                -- A Freeze/Gymban blacklist must not silently disable Aura.
                if other ~= Player and other.Parent == Players
                    and not inPlayerList(State.Whitelist, other) then
                    local targetChar = other.Character
                    local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
                    local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
                    if targetHum and targetHum.Health > 0 and targetRoot then
                        -- Full 360-degree check: no camera or facing-angle restriction.
                        local distance = (root.Position - targetRoot.Position).Magnitude
                        if distance <= radius and distance > 0.5 then
                            local relative = targetRoot.Position - root.Position
                            local forward = root.CFrame.LookVector
                            local flatDirection = Vector3.new(relative.X, 0, relative.Z)
                            local facing = false
                            if flatDirection.Magnitude > 0.05 then
                                facing = Vector3.new(forward.X, 0, forward.Z):Dot(flatDirection.Unit) > 0.20
                            end
                            eligible[#eligible + 1] = {
                                player = other, root = targetRoot, distance = distance,
                                facing = facing,
                            }
                        end
                    end
                end
            end
            if #eligible == 0 then return nil end
            -- 360 scan with nearest-first selection, including players behind
            -- the avatar. Aiming never changes the avatar's own CFrame.
            table.sort(eligible, function(a, b)
                if a.distance ~= b.distance then return a.distance < b.distance end
                return a.player.UserId < b.player.UserId
            end)
            return eligible[1], root, hum
        end

        local function cursorInsideHub(x, y)
            if not Holder.Visible then return false end
            local topLeft = Holder.AbsolutePosition
            local size = Holder.AbsoluteSize
            return x >= topLeft.X and x <= topLeft.X + size.X
                and y >= topLeft.Y and y <= topLeft.Y + size.Y
        end

        local function mouseIsOverHub()
            local pointer = UIS:GetMouseLocation()
            return cursorInsideHub(pointer.X, pointer.Y)
        end

        local function chooseGameplayClickPoint(viewport)
            -- Avoid both the screen edge (where mobile/Roblox UI lives) and
            -- any location occupied by our own GUI. Mouse position alone
            -- should never be changed, and the avatar must never rotate.
            local candidates = {
                Vector2.new(viewport.X * 0.50, viewport.Y * 0.52),
                Vector2.new(viewport.X * 0.78, viewport.Y * 0.52),
                Vector2.new(viewport.X * 0.22, viewport.Y * 0.52),
                Vector2.new(viewport.X * 0.65, viewport.Y * 0.76),
                Vector2.new(viewport.X * 0.35, viewport.Y * 0.76),
            }
            for _, point in ipairs(candidates) do
                if not cursorInsideHub(point.X, point.Y) then
                    return math.floor(point.X), math.floor(point.Y)
                end
            end
            return nil, nil
        end

        local PUNCH_HOLD_TIME = 0.07 -- cover a full input frame, including async M1 handling
        local function clickUsingVIM(target)
            if not vim then return false, "VIM input unavailable" end
            local camera = workspace.CurrentCamera
            if not camera then return false, "No camera available" end
            local x, y = nil, nil
            local originalCamera, aimedCamera = nil, nil
            local aimConnection = nil
            local localPulse = false
            local aimPosition = target and target.root and target.root.Parent
                and (target.root.Position + Vector3.new(0, 0.8, 0)) or nil

            local function restoreCamera()
                if aimConnection then
                    aimConnection:Disconnect()
                    aimConnection = nil
                end
                if originalCamera then
                    pcall(function()
                        if workspace.CurrentCamera == camera then
                            camera.CFrame = originalCamera
                        end
                    end)
                end
            end

            if aimPosition then
                local point, inView = camera:WorldToViewportPoint(aimPosition)
                if inView and point.Z > 0
                    and not cursorInsideHub(point.X, point.Y) then
                    x, y = math.floor(point.X), math.floor(point.Y)
                else
                    -- Camera.CFrame is client-local; it is not the avatar's
                    -- facing CFrame. Keep it aimed through button-down/up so
                    -- an asynchronously handled game M1 sees the same ray.
                    local before = camera.CFrame
                    if (aimPosition - before.Position).Magnitude > 0.1 then
                        local ok = pcall(function()
                            local aimed = CFrame.lookAt(before.Position, aimPosition)
                            camera.CFrame = aimed
                            local projected, visible = camera:WorldToViewportPoint(aimPosition)
                            if visible and projected.Z > 0
                                and not cursorInsideHub(projected.X, projected.Y) then
                                x, y = math.floor(projected.X), math.floor(projected.Y)
                                originalCamera, aimedCamera = before, aimed
                                localPulse = true
                            end
                        end)
                        if not ok then x, y = nil, nil end
                    end
                    if not originalCamera then
                        pcall(function() camera.CFrame = before end)
                    end
                end
            else
                x, y = chooseGameplayClickPoint(camera.ViewportSize)
            end

            if not x then
                restoreCamera()
                return false, "Target not aimable: hide VOID HUB or use LEGACY"
            end

            if aimedCamera then
                aimConnection = RunService.Heartbeat:Connect(function()
                    if not enabled or not alive or workspace.CurrentCamera ~= camera then
                        restoreCamera()
                        return
                    end
                    -- Follow a moving target locally during this single
                    -- M1 press. No HumanoidRootPart or AutoRotate changes.
                    if target and target.root and target.root.Parent then
                        local goal = target.root.Position + Vector3.new(0, 0.8, 0)
                        pcall(function()
                            camera.CFrame = CFrame.lookAt(originalCamera.Position, goal)
                        end)
                    else
                        restoreCamera()
                    end
                end)
            end

            local downOk, downError = pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
            end)
            if not downOk then
                restoreCamera()
                return false, "VIM press failed: " .. tostring(downError)
            end

            task.wait(PUNCH_HOLD_TIME)
            local upOk, upError = pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
            end)
            restoreCamera()
            if not upOk then return false, "VIM release failed: " .. tostring(upError) end
            return true, localPulse and "VIM full-press local 360 ray" or "VIM screen-point aim"
        end

        local function clickUsingLegacy()
            if mouseIsOverHub() then
                return false, "Move the real cursor away from VOID HUB, or select VIM."
            end
            if type(mouse1press) == "function" and type(mouse1release) == "function" then
                local downOk, downErr = pcall(mouse1press)
                if downOk then
                    task.wait(PUNCH_HOLD_TIME)
                    local upOk, upErr = pcall(mouse1release)
                    if upOk then return true, "Legacy hold" end
                    return false, "Legacy release failed: " .. tostring(upErr)
                end
            end
            if type(mouse1click) == "function" then
                local ok, err = pcall(mouse1click)
                if ok then return true, "Legacy click" end
                return false, "Legacy click failed: " .. tostring(err)
            end
            return false, "Legacy mouse input unavailable"
        end

        local function clickUsingPCAura()
            if not vim then return false, "PC Aura requires VirtualInputManager" end
            local camera = workspace.CurrentCamera
            if not camera then return false, "No camera available" end
            local viewport = camera.ViewportSize
            local x, y = math.floor(viewport.X / 2), math.floor(viewport.Y / 2)
            if cursorInsideHub(x, y) then
                x, y = chooseGameplayClickPoint(viewport)
            end
            if not x then return false, "Close or minimize VOID HUB to free the click area" end
            -- Friend's 0.0001-second click can be shorter than one render
            -- frame. Keep a brief but measurable down/up M1 signal.
            local okDown, downError = pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, true, game, 1)
            end)
            if not okDown then return false, "PC Aura input down failed: " .. tostring(downError) end
            task.wait(0.03)
            local okUp, upError = pcall(function()
                vim:SendMouseButtonEvent(x, y, 0, false, game, 1)
            end)
            if not okUp then return false, "PC Aura input up failed: " .. tostring(upError) end
            return true, "PC center click + hitbox"
        end

        local function simulateNormalClick(target)
            -- PC matches the friend's range-gated invisible-hitbox approach.
            -- Other input backends remain unchanged for comparison.
            if inputMode == "PC" then
                if playerHitboxesActive() then
                    return false, "Disable separate Player Hitboxes before PC Aura"
                end
                return clickUsingPCAura()
            end
            if inputMode == "LEGACY" then return clickUsingLegacy() end
            if inputMode == "VIM" then return clickUsingVIM(target) end
            local ok, backend = clickUsingVIM(target)
            if ok then return ok, backend end
            if not mouseIsOverHub() then
                local fallback, method = clickUsingLegacy()
                if fallback then return fallback, method end
            end
            return false, "AUTO input unavailable: " .. tostring(backend)
        end

        local function attemptNoTurnClick(target, root, humanoid)
            if not target or not target.root or not target.root.Parent
                or not root or not root.Parent or not humanoid or humanoid.Health <= 0 then
                return false, "Target or character is no longer available."
            end
            -- No character CFrame writes, turning or teleporting. The camera
            -- pulse is local and immediately restored; hits remain game-owned.
            if inputMode == "PC" and pcTargetRoot ~= target.root then
                return false, "PC Aura target hitbox not ready"
            end
            return simulateNormalClick(target)
        end

        -- Count real input events observed by this client (NOT confirmed hits).
        bindGlobal(UIS.InputBegan, function(input, processed)
            if input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
                observedClicks += 1
                lastObservedClick = os.clock()
            end
        end)
        persistentToggle(toggle, function()
            readSettings()
            enabled = not enabled
            if not enabled then restorePCHitbox() end
            nextClickAt = os.clock() + 0.35 -- allow GUI button click to finish
            render()
            if enabled then
                setStatus(("ON. 360 target scan to %d studs; %.1f attack attempts/sec via %s. Hits depend on server.")
                    :format(radius, hitSpeed, inputMode))
            else
                setStatus("OFF. Automatic clicks stopped. Click attempts this session: " .. tostring(clicks))
            end
        end)
        rangeBox.FocusLost:Connect(readSettings)
        intervalBox.FocusLost:Connect(readSettings)
        savedApply[#savedApply + 1] = readSettings

        bindGlobal(RunService.Heartbeat, function()
            if not alive or not Gui.Parent then return end
            if not enabled then
                if pcTargetRoot then restorePCHitbox() end
                return
            end
            local now = os.clock()
            -- Keep PC's ONE nearest target current, regardless of which
            -- direction the avatar is facing. This is not server-side damage.
            if now - scannedAt >= 0.025 then
                scannedAt = now
                local targetForHitbox = findNextTarget()
                updatePCHitbox(targetForHitbox)
            end
            if clicking or UIS:GetFocusedTextBox()
                or UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
                return
            end
            if now < nextClickAt then return end
            local target, root, humanoid = findNextTarget()
            if not target then
                setStatus("ON. No eligible players within " .. tostring(radius) .. " studs (all directions, whitelist excluded).")
                return
            end
            if inputMode == "PC" and not pcTargetRoot then
                if playerHitboxesActive() then
                    setStatus("PC Aura: switch Player Hitboxes OFF to avoid conflicting hitbox edits.")
                    return
                end
                updatePCHitbox(target)
            end
            nextClickAt = now + (1 / hitSpeed)
            clicking = true
            task.spawn(function()
                if not enabled or not alive or not Gui.Parent then
                    clicking = false
                    return
                end
                -- Continuous 360 detection, but avatar never turns automatically.
                local sent, methodOrError = attemptNoTurnClick(target, root, humanoid)
                if sent then
                    clicks += 1
                    if enabled and os.clock() - lastClickStatusAt >= 0.40 then
                        lastClickStatusAt = os.clock()
                        setStatus(("ON. %d M1 sends via %s | %s (%.1f studs, %s) | %.1f/sec. Hits unconfirmed.")
                            :format(clicks, methodOrError, target.player.Name, target.distance,
                                target.facing and "front" or "behind", hitSpeed))
                    end
                else
                    setStatus("KILL AURA: " .. tostring(methodOrError))
                    -- Keep the toggle ON for retry or backend switching;
                    -- avoid infinite bursts when the client has no input API.
                    nextClickAt = os.clock() + 0.8
                end
                clicking = false
            end)
        end)
        Gui.Destroying:Connect(function()
            enabled, alive = false, false
            restorePCHitbox()
            if releasePCAuraHitbox == restorePCHitbox then
                releasePCAuraHitbox = nil
            end
        end)
        render()
        setStatus("OFF. Enable Kill Aura to target nearby players. Actual hits depend on game rules.")

        -- Preserve older stacked-card coordinates; the final layout pass
        -- reflows the larger Aura card from its actual Size.
        for _, child in ipairs(page:GetChildren()) do
            if child ~= card and child:IsA("GuiObject")
                and child.Position.Y.Scale == 0 and child.Position.Y.Offset >= 478 then
                local p = child.Position
                child.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale, p.Y.Offset + 167)
            end
        end
        page.CanvasSize = UDim2.fromOffset(0, page.CanvasSize.Y.Offset + 167)
    end
end


-- =====================================================================
-- ATTACK: TP PUSH FORCEFIELD (SMOOTH/LOW-OVERHEAD)
-- Preserve the CarryRequest -> EventTeleportEvent -> StopCarry workflow,
-- the adjustable 3-50 stud radius and existing safety/whitelist behavior.
-- A client-local matte bubble follows render frames; proximity scans are
-- sampled at a modest interval, not every Heartbeat. Per-target re-entry
-- cannot bypass its cooldown and create repeated visible server teleports.
-- Server owns resulting movement; true remote teleport interpolation is
-- not possible from this client. Never freeze normal self movement.
-- =====================================================================
do
    local page = pages["Attack"]
    if page then
        local headingY = page.CanvasSize.Y.Offset + 10
        local heading = Instance.new("TextLabel")
        heading.Name = "PushForcefieldHeading"
        heading.Position = UDim2.fromOffset(3, headingY)
        heading.Size = UDim2.fromOffset(875, 27)
        heading.BackgroundTransparency = 1
        heading.Font = Enum.Font.GothamBold
        heading.TextSize = 12
        heading.TextColor3 = Color3.fromRGB(73, 111, 174)
        heading.TextXAlignment = Enum.TextXAlignment.Left
        heading.Text = "05    FORCEFIELD"
        heading.Parent = page

        local divider = Instance.new("Frame")
        divider.Name = "PushForcefieldDivider"
        divider.Position = UDim2.fromOffset(2, headingY + 29)
        divider.Size = UDim2.fromOffset(876, 1)
        divider.BackgroundColor3 = Color3.fromRGB(219, 225, 237)
        divider.BorderSizePixel = 0
        divider.Parent = page

        local cardY = headingY + 40
        local card = makeFeatureCard(page, "Forcefield", cardY)
        card.Name = "AttackPushForcefield"
        card.Size = UDim2.fromOffset(880, 178)
        card:FindFirstChildOfClass("TextLabel").Size = UDim2.fromOffset(835, 24)
        page.CanvasSize = UDim2.fromOffset(0, cardY + 203)

        local toggle = Instance.new("TextButton")
        toggle.Name = "ForcefieldToggle"
        toggle.Position = UDim2.fromOffset(16, 51)
        toggle.Size = UDim2.fromOffset(205, 36)
        toggle.Font = Enum.Font.GothamBold
        toggle.TextSize = 12
        toggle.AutoButtonColor = false
        toggle.Parent = card
        corner(toggle, 8)

        local radiusLabel = Instance.new("TextLabel")
        radiusLabel.Name = "ForcefieldRadiusLabel"
        radiusLabel.Position = UDim2.fromOffset(241, 51)
        radiusLabel.Size = UDim2.fromOffset(111, 36)
        radiusLabel.BackgroundTransparency = 1
        radiusLabel.Font = Enum.Font.GothamBold
        radiusLabel.TextSize = 12
        radiusLabel.TextColor3 = Color3.fromRGB(40, 42, 55)
        radiusLabel.Text = "Radius (3-50):"
        radiusLabel.Parent = card

        local radiusInput = Instance.new("TextBox")
        radiusInput.Name = "ForcefieldRadius"
        radiusInput.Position = UDim2.fromOffset(360, 51)
        radiusInput.Size = UDim2.fromOffset(79, 36)
        radiusInput.BackgroundColor3 = Color3.fromRGB(243, 246, 252)
        radiusInput.TextColor3 = Color3.fromRGB(35, 38, 47)
        radiusInput.Font = Enum.Font.GothamBold
        radiusInput.TextSize = 13
        radiusInput.Text = "5"
        radiusInput.PlaceholderText = "3-50"
        radiusInput.ClearTextOnFocus = false
        radiusInput.Parent = card
        corner(radiusInput, 8)

        local applyButton = Instance.new("TextButton")
        applyButton.Name = "ForcefieldApply"
        applyButton.Position = UDim2.fromOffset(450, 51)
        applyButton.Size = UDim2.fromOffset(103, 36)
        applyButton.Text = "APPLY"
        applyButton.Font = Enum.Font.GothamBold
        applyButton.TextSize = 12
        applyButton.AutoButtonColor = false
        applyButton.Parent = card
        corner(applyButton, 8)
        animateToggle(applyButton, false)

        local info = Instance.new("TextLabel")
        info.Name = "ForcefieldStatus"
        info.Position = UDim2.fromOffset(16, 103)
        info.Size = UDim2.fromOffset(844, 62)
        info.BackgroundTransparency = 1
        info.TextWrapped = true
        info.TextXAlignment = Enum.TextXAlignment.Left
        info.TextYAlignment = Enum.TextYAlignment.Top
        info.Font = Enum.Font.Gotham
        info.TextSize = 12
        info.TextColor3 = Color3.fromRGB(60, 69, 83)
        info.Parent = card

        local ReplicatedStorage = game:GetService("ReplicatedStorage")
        local enabled, alive, busy = false, true, false
        local radius, requestCount = 5, 0
        local bubble, statusClock = nil, 0
        local scanClock = 0
        local lastTargetRequest = {}
        local lastRequestAt = -math.huge
        local nearbyCount = 0
        -- Track physical edge contacts separately from repeat cooldowns.
        -- First entry gets immediate priority even if an old retry is cooling down.
        local touchingLastFrame = {}
        local waitingFirstPush = {}
        local shownToggleState = nil
        local returnHoldConnection = nil
        local returnHoldVisualConnection = nil
        local function stopOwnPositionHold()
            if returnHoldConnection then
                returnHoldConnection:Disconnect()
                returnHoldConnection = nil
            end
            if returnHoldVisualConnection then
                returnHoldVisualConnection:Disconnect()
                returnHoldVisualConnection = nil
            end
        end
        local function holdOwnPosition(saved, ownChar, duration)
            -- The old version forced CFrame and zero velocity EVERY frame.
            -- At 50 studs, repeated pushes made this a permanent movement
            -- lock. Correct only a genuine large teleport, at most twice.
            stopOwnPositionHold()
            local since = os.clock()
            local corrected, lastCorrectionAt = 0, -math.huge
            local function maintainPosition()
                local now = os.clock()
                if not enabled or not alive or not Gui.Parent
                    or Player.Character ~= ownChar or DeathTPIsEscaping
                    or now - since >= duration then
                    stopOwnPositionHold()
                    return
                end
                local hrp = ownChar:FindFirstChild("HumanoidRootPart")
                local hum = ownChar:FindFirstChildOfClass("Humanoid")
                if not hrp or not hrp.Parent or not hum or hum.Health <= 0 then
                    stopOwnPositionHold()
                    return
                end
                if corrected < 2 and now - lastCorrectionAt >= 0.12
                    and hum.MoveDirection.Magnitude < 0.05
                    and (hrp.Position - saved.Position).Magnitude > 18 then
                    corrected += 1
                    lastCorrectionAt = now
                    hrp.CFrame = saved
                    hrp.AssemblyLinearVelocity = Vector3.zero
                    hrp.AssemblyAngularVelocity = Vector3.zero
                end
            end
            -- Physics-only correction: no RenderStepped self-position writes
            -- that would make our own avatar appear to stutter.
            returnHoldConnection = RunService.Heartbeat:Connect(maintainPosition)
            maintainPosition()
        end
        local note = "OFF. Clean proximity shield: cooldowns reduce visible teleport jitter."
        -- One request at a time. Large 50-stud jumps must not repeat rapidly.
        local GLOBAL_COOLDOWN = 0.85
        local TARGET_COOLDOWN = 2.50
        local SCAN_INTERVAL = 0.08
        local STATUS_INTERVAL = 1.0
        local BUBBLE_ALPHA = 0.93
        local CONTACT_EPSILON = 0.01 -- studs: allow tiny boundary contact; not a timing promise
        local PUSH_EXTRA_STUDS = 8 -- land 8 studs outside the chosen bubble radius
        local EVENT_POSITION = Vector3.new(53.5, 8.298911, 118.149994)

        -- A bubble is a sphere, body parts are oriented boxes. Check their
        -- closest surface point instead of checking only HumanoidRootPart center.
        -- Accessories and equipped tools are intentionally ignored.
        local function bodyTouchesBubble(character, center, bubbleRadius, rootDistance)
            if rootDistance > bubbleRadius + 8 then return false end
            local squaredLimit = (bubbleRadius + CONTACT_EPSILON) ^ 2
            for _, limb in ipairs(character:GetChildren()) do
                if limb:IsA("BasePart") and limb.Size.Magnitude < 18 then
                    local relative = limb.CFrame:PointToObjectSpace(center)
                    local half = limb.Size * 0.5
                    local dx = math.max(math.abs(relative.X) - half.X, 0)
                    local dy = math.max(math.abs(relative.Y) - half.Y, 0)
                    local dz = math.max(math.abs(relative.Z) - half.Z, 0)
                    if dx * dx + dy * dy + dz * dz <= squaredLimit then
                        return true
                    end
                end
            end
            return false
        end

        local function showState(nextNote)
            if nextNote then note = nextNote end
            if not alive or not Gui.Parent then return end
            if shownToggleState ~= enabled then
                shownToggleState = enabled
                toggle.Text = enabled and "FORCEFIELD: ON" or "FORCEFIELD: OFF"
                animateToggle(toggle, enabled)
            end
            info.Text = ("%s\nRadius: %d studs | Nearby: %d | Push attempts: %d | +%d studs outside.")
                :format(note, radius, nearbyCount, requestCount, PUSH_EXTRA_STUDS)
        end

        local function removeBubble()
            if bubble then pcall(function() bubble:Destroy() end) bubble = nil end
        end

        local function makeBubble()
            removeBubble()
            local part = Instance.new("Part")
            part.Name = "VoidHubV1_TPPushBubble"
            part.Shape = Enum.PartType.Ball
            part.Anchored = true
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.CastShadow = false
            -- SmoothPlastic avoids the flickering animated ForceField texture,
            -- especially when the radius is set to 50 studs.
            part.Material = Enum.Material.SmoothPlastic
            part.Color = Color3.fromRGB(224, 231, 240)
            part.Transparency = BUBBLE_ALPHA
            part.Reflectance = 0
            part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
            local root = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
            if root then part.CFrame = CFrame.new(root.Position) end
            part.Parent = workspace.CurrentCamera or workspace
            bubble = part
        end

        local function setRadius()
            local n = tonumber(radiusInput.Text)
            if not n or n ~= n or n == math.huge or n == -math.huge then
                radiusInput.Text = tostring(radius)
                showState("Enter a valid number of studs, from 3 to 50.")
                return
            end
            radius = math.clamp(math.floor(n + 0.5), 3, 50)
            table.clear(touchingLastFrame)
            table.clear(waitingFirstPush)
            radiusInput.Text = tostring(radius)
            if bubble and bubble.Parent then
                bubble.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
            end
            showState(enabled and "ON. Radius changed." or "Radius saved.")
        end

        local function validRemotes()
            local carry = ReplicatedStorage:FindFirstChild("CarryRequest")
            local stop = ReplicatedStorage:FindFirstChild("StopCarry")
            local system = ReplicatedStorage:FindFirstChild("EventInviteSystem")
            local event = (system and system:FindFirstChild("EventTeleportEvent"))
                or ReplicatedStorage:FindFirstChild("EventTeleportEvent")
            if carry and carry:IsA("RemoteEvent")
                and stop and stop:IsA("RemoteEvent")
                and event and event:IsA("RemoteEvent") then
                return carry, event, stop
            end
            return nil
        end

        persistentToggle(toggle, function()
            enabled = not enabled
            nearbyCount = 0
            scanClock, statusClock = 0, 0
            table.clear(touchingLastFrame)
            table.clear(waitingFirstPush)
            if enabled then
                local carry = validRemotes()
                if not carry then
                    enabled = false
                    showState("Game Bring/Carry remotes unavailable. No TP push possible here.")
                    return
                end
                makeBubble()
                showState("ON. Smooth shield; nearby contacts checked at 0.08s intervals.")
            else
                stopOwnPositionHold()
                removeBubble()
                showState("OFF. All new TP-push requests stopped.")
            end
        end)
        applyButton.Activated:Connect(setRadius)
        savedApply[#savedApply + 1] = setRadius
        radiusInput.FocusLost:Connect(function()
            if radiusInput.Text ~= tostring(radius) then setRadius() end
        end)

        -- Based on Bring's existing offset convention: event coordinate - desired coordinate.
        local function requestTeleportPush(target, desiredPosition)
            -- Serialize this sequence with other Bring/Gymban actions, and
            -- always release the shared owner if the target disappears.
            local function finish()
                if SharedTeleportOwner == "Forcefield" then
                    SharedTeleportOwner = nil
                    SharedTeleportCooldownUntil = math.max(
                        SharedTeleportCooldownUntil, os.clock() + 0.18)
                end
                busy = false
            end
            local carry, event, stop = validRemotes()
            if isManualGrabWindow() then
                finish()
                return -- manual G owns carry until its completion
            end
            if not carry then
                finish()
                showState("Bring remotes missing. Can't request TP push.")
                return
            end
            local ownChar = Player.Character
            local root = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
            local human = ownChar and ownChar:FindFirstChildOfClass("Humanoid")
            if not root or not human or human.Health <= 0 then finish() return end
            local saved = root.CFrame
            local offset = EVENT_POSITION - desiredPosition
            local function round(v)
                return math.floor(v + 0.5)
            end
            local carried, eventSent = false, false
            -- Start holding BEFORE CarryRequest so our own character never
            -- visibly jumps while the server processes the remote.
            holdOwnPosition(saved, ownChar, 0.80)
            local ok = pcall(function()
                AntiTPIntentionalTeleportUntil = os.clock() + 1.6
                carry:FireServer(target, round(offset.X), round(offset.Y),
                    round(offset.Z), 0, 0, 0)
                carried = true
                task.wait(0.065) -- shorter handoff without eliminating the sync gap
                -- Only execute an outstanding request while its original target is valid.
                if alive and enabled and not isManualGrabWindow()
                    and target.Parent == Players and Player.Character == ownChar
                    and human.Health > 0 then
                    event:FireServer()
                    eventSent = true
                end
            end)
            -- Do not reset our position/velocity for a normal step or turn.
            -- Only correct a large unwanted event teleport while not walking.
            pcall(function()
                if Player.Character == ownChar and root.Parent
                    and not isManualGrabWindow()
                    and human.MoveDirection.Magnitude < 0.05
                    and (root.Position - saved.Position).Magnitude > 18 then
                    root.CFrame = saved
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end
            end)
            if carried and not isManualGrabWindow() then
                holdOwnPosition(saved, ownChar, 0.60)
                task.wait(0.05)
                if not isManualGrabWindow() then
                    pcall(function() stop:FireServer() end)
                end
            else
                -- An automatic push must not end a real manual G grab.
                stopOwnPositionHold()
            end
            if ok and eventSent then
                requestCount += 1
                if alive and enabled then
                    showState("Push request sent for " .. target.Name ..
                        ". Server determines if the target moves.")
                end
            else
                if alive and enabled then showState("TP-push request failed locally.") end
            end
            finish()
        end

        -- The local visual follows the avatar once per rendered frame.
        -- No teleport requests or expensive nearby-player scans here.
        bindGlobal(RunService.RenderStepped, function()
            if not enabled or not alive or not Gui.Parent or not bubble or not bubble.Parent then
                return
            end
            local char = Player.Character
            local root = char and char:FindFirstChild("HumanoidRootPart")
            if root then bubble.CFrame = CFrame.new(root.Position) end
        end)

        bindGlobal(RunService.Heartbeat, function(dt)
            if not alive or not enabled or not Gui.Parent then return end
            local ownChar = Player.Character
            local root = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
            local hum = ownChar and ownChar:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health <= 0 or root.Anchored or DeathTPIsEscaping then
                if bubble then bubble.Transparency = 1 end
                return
            end
            if not bubble or not bubble.Parent then makeBubble() end
            if bubble.Transparency ~= BUBBLE_ALPHA then bubble.Transparency = BUBBLE_ALPHA end
            local elapsed = math.clamp(tonumber(dt) or 0, 0, 0.1)
            statusClock += elapsed
            scanClock += elapsed
            -- At 50 studs, 60 scans/sec of every limb is unnecessary.
            -- 0.08s sampling stays responsive while reducing CPU cost.
            if scanClock < SCAN_INTERVAL then return end
            scanClock = 0
            local now = os.clock()
            local eligible = {}
            local touchingThisFrame = {}
            local urgentEntry = false
            nearbyCount = 0

            -- Collect ALL unwhitelisted players currently inside the bubble.
            -- No "one entry only" latch; people still inside can be pushed
            -- again after a per-player cooldown.
            for _, other in ipairs(Players:GetPlayers()) do
                if other ~= Player and not inPlayerList(State.Whitelist, other) then
                    local char = other.Character
                    local otherRoot = char and char:FindFirstChild("HumanoidRootPart")
                    local otherHum = char and char:FindFirstChildOfClass("Humanoid")
                    if otherRoot and otherHum and otherHum.Health > 0 then
                        local relative = otherRoot.Position - root.Position
                        local distance = relative.Magnitude
                        if bodyTouchesBubble(char, root.Position, radius, distance) then
                            nearbyCount += 1
                            local uid = other.UserId
                            touchingThisFrame[uid] = true
                            if not touchingLastFrame[uid] then
                                waitingFirstPush[uid] = true
                            end
                            local firstTouch = waitingFirstPush[uid] == true
                            local since = now - (lastTargetRequest[uid] or -math.huge)
                            -- Re-entering or hovering at the boundary must
                            -- NOT bypass the per-player cooldown.
                            if since >= TARGET_COOLDOWN then
                                local flat = Vector3.new(relative.X, 0, relative.Z)
                                if flat.Magnitude < 0.15 then
                                    local look = otherRoot.CFrame.LookVector
                                    flat = Vector3.new(look.X, 0, look.Z)
                                    if flat.Magnitude < 0.05 then flat = Vector3.new(1, 0, 0) end
                                end
                                if firstTouch then urgentEntry = true end
                                eligible[#eligible + 1] = {
                                    player = other,
                                    offset = flat,
                                    y = otherRoot.Position.Y,
                                    distance = distance,
                                    since = since,
                                    firstTouch = firstTouch,
                                }
                            end
                        end
                    end
                end
            end

            -- A fresh body/edge contact bypasses only the normal repeat
            -- throttle. Never overlap Carry sequences or bypass shared safety.
            for uid in pairs(touchingLastFrame) do
                if not touchingThisFrame[uid] then
                    waitingFirstPush[uid] = nil
                end
            end
            touchingLastFrame = touchingThisFrame
            if not busy and #eligible > 0
                and not isManualGrabWindow() and not SharedTeleportOwner
                and now >= SharedTeleportCooldownUntil
                and (urgentEntry or now - lastRequestAt >= GLOBAL_COOLDOWN) then
                table.sort(eligible, function(a, b)
                    if a.firstTouch ~= b.firstTouch then return a.firstTouch end
                    if a.distance ~= b.distance then return a.distance < b.distance end
                    return a.player.UserId < b.player.UserId
                end)
                local entry = eligible[1]
                waitingFirstPush[entry.player.UserId] = nil
                local destOffset = entry.offset.Unit * (radius + PUSH_EXTRA_STUDS)
                local desired = Vector3.new(
                    root.Position.X + destOffset.X,
                    entry.y,
                    root.Position.Z + destOffset.Z
                )
                lastRequestAt = now
                lastTargetRequest[entry.player.UserId] = now
                busy = true
                SharedTeleportOwner = "Forcefield"
                task.spawn(requestTeleportPush, entry.player, desired)
            end

            if statusClock >= STATUS_INTERVAL then
                statusClock = 0
                if not busy then
                    if nearbyCount > 0 then
                        showState("ON. " .. nearbyCount .. " nearby; calm scan and spaced push requests.")
                    else
                        showState("ON. Shield clear. Watching for nearby players.")
                    end
                end
            end
        end)

        bindGlobal(Players.PlayerRemoving, function(leaving)
            lastTargetRequest[leaving.UserId] = nil
            touchingLastFrame[leaving.UserId] = nil
            waitingFirstPush[leaving.UserId] = nil
        end)
        Gui.Destroying:Connect(function()
            enabled, alive = false, false
            if SharedTeleportOwner == "Forcefield" then SharedTeleportOwner = nil end
            stopOwnPositionHold()
            removeBubble()
            table.clear(lastTargetRequest)
            table.clear(touchingLastFrame)
            table.clear(waitingFirstPush)
        end)
        showState()
    end
end

-- ============================================================================
-- DEFENSE: COUNTER TP (EXPERIMENTAL / NO BUBBLE)
-- Requires damage and a nearby attacker; standing close is never enough.
-- CarryRequest -> EventTeleportEvent -> StopCarry is server-authoritative.
-- ============================================================================
do
    local RS = game:GetService("ReplicatedStorage")
    local card = makeFeatureCard(pages["Attack"], "Counter TP | On Hit", 0)
    card.Name = "AttackCounterTP"
    card.Size = UDim2.fromOffset(880, 176)
    local title = card:FindFirstChildOfClass("TextLabel")
    if title then title.Size = UDim2.fromOffset(720, 24) end

    local button = Instance.new("TextButton")
    button.Name = "CounterTPToggle"
    button.Position = UDim2.fromOffset(16, 49)
    button.Size = UDim2.fromOffset(204, 36)
    button.AutoButtonColor = false
    button.Font = Enum.Font.GothamBold
    button.TextSize = 12
    button.Parent = card
    corner(button, 8)

    local label = Instance.new("TextLabel")
    label.Name = "CounterTPRadiusLabel"
    label.Position = UDim2.fromOffset(240, 49)
    label.Size = UDim2.fromOffset(113, 36)
    label.BackgroundTransparency = 1
    label.Text = "Radius (1-5):"
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(35, 39, 47)
    label.Parent = card

    local radiusBox = Instance.new("TextBox")
    radiusBox.Name = "CounterTPRadius"
    radiusBox.Position = UDim2.fromOffset(359, 49)
    radiusBox.Size = UDim2.fromOffset(77, 36)
    radiusBox.Text = "3"
    radiusBox.PlaceholderText = "1-5"
    radiusBox.ClearTextOnFocus = false
    radiusBox.BackgroundColor3 = Color3.fromRGB(240, 243, 248)
    radiusBox.TextColor3 = Color3.fromRGB(34, 38, 47)
    radiusBox.Font = Enum.Font.GothamBold
    radiusBox.TextSize = 13
    radiusBox.Parent = card
    corner(radiusBox, 8)
    stroke(radiusBox, Color3.fromRGB(201, 207, 216), 1)

    local apply = Instance.new("TextButton")
    apply.Name = "CounterTPApply"
    apply.Position = UDim2.fromOffset(449, 49)
    apply.Size = UDim2.fromOffset(105, 36)
    apply.Text = "APPLY"
    apply.Font = Enum.Font.GothamBold
    apply.TextSize = 12
    apply.AutoButtonColor = false
    apply.Parent = card
    corner(apply, 8)
    animateToggle(apply, false)

    local status = Instance.new("TextLabel")
    status.Name = "CounterTPStatus"
    status.Position = UDim2.fromOffset(16, 103)
    status.Size = UDim2.fromOffset(842, 61)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(63, 70, 82)
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextYAlignment = Enum.TextYAlignment.Top
    status.TextSize = 12
    status.TextWrapped = true
    status.Font = Enum.Font.Gotham
    status.Parent = card

    local enabled, alive, busy = false, true, false
    local radius, attempts = 3, 0
    local note = "OFF. No proximity trigger; waits for real health loss."
    local lastState, generation, damageConn = nil, 0, nil
    local lastHitAt, lastAttemptAt = -math.huge, -math.huge
    local perTarget = {}
    local GLOBAL_COOLDOWN, TARGET_COOLDOWN = 0.8, 3.0

    local function render(message)
        if message then note = message end
        if not alive or not Gui.Parent then return end
        if lastState ~= enabled then
            lastState = enabled
            button.Text = enabled and "COUNTER TP: ON" or "COUNTER TP: OFF"
            animateToggle(button, enabled)
        end
        status.Text = ("%s\nRange: %d studs | Requests: %d | No bubble; whitelist protected.")
            :format(note, radius, attempts)
    end

    local function changeRadius()
        local n = tonumber(radiusBox.Text)
        if not n or n ~= n or n == math.huge or n == -math.huge then
            radiusBox.Text = tostring(radius)
            render("Please enter 1-5 studs.")
            return
        end
        radius = math.clamp(math.floor(n + 0.5), 1, 5)
        radiusBox.Text = tostring(radius)
        render(enabled and "ON. New hit radius applied." or "Radius saved; toggle ON to test.")
    end
    apply.Activated:Connect(changeRadius)
    radiusBox.FocusLost:Connect(function()
        if radiusBox.Text ~= tostring(radius) then changeRadius() end
    end)
    savedApply[#savedApply + 1] = changeRadius

    local function remotes()
        local carry = RS:FindFirstChild("CarryRequest")
        local stop = RS:FindFirstChild("StopCarry")
        local folder = RS:FindFirstChild("EventInviteSystem")
        local ev = (folder and folder:FindFirstChild("EventTeleportEvent"))
            or RS:FindFirstChild("EventTeleportEvent")
        if carry and carry:IsA("RemoteEvent") and stop
            and stop:IsA("RemoteEvent") and ev and ev:IsA("RemoteEvent") then
            return carry, ev, stop
        end
        return nil
    end

    local function nearby(other, root)
        if not other or other == Player or other.Parent ~= Players
            or inPlayerList(State.Whitelist, other) then return false end
        local c = other.Character
        local r = c and c:FindFirstChild("HumanoidRootPart")
        local h = c and c:FindFirstChildOfClass("Humanoid")
        return r ~= nil and h ~= nil and h.Health > 0
            and (r.Position - root.Position).Magnitude <= radius
    end

    local function findAttacker(humanoid, root)
        local tag = humanoid:FindFirstChild("creator")
        if tag and tag:IsA("ObjectValue") then
            local p = tag.Value
            if p and p:IsA("Player") and nearby(p, root) then
                return p, "damage tag"
            end
        end
        -- Untagged damage: do not guess when more than one player is nearby.
        local one, count = nil, 0
        for _, candidate in ipairs(Players:GetPlayers()) do
            if nearby(candidate, root) then
                count += 1
                one = candidate
                if count > 1 then return nil, "ambiguous attacker" end
            end
        end
        return one, one and "one nearby player" or "no nearby attacker"
    end

    local function sendCounter(target, ownChar, revision)
        local function finish()
            if SharedTeleportOwner == "CounterTP" then
                SharedTeleportOwner = nil
                SharedTeleportCooldownUntil = math.max(
                    SharedTeleportCooldownUntil, os.clock() + 0.3)
            end
            busy = false
        end
        local carry, ev, stop = remotes()
        local root = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
        local hum = ownChar and ownChar:FindFirstChildOfClass("Humanoid")
        if not carry or not root or not hum or hum.Health <= 0
            or Player.Character ~= ownChar or not target.Parent
            or isManualGrabWindow() or DeathTPIsEscaping then
            if not carry then render("Game classroom Carry remotes unavailable.") end
            finish()
            return
        end
        local originalPosition = root.CFrame
        local didCarry, didEvent = false, false
        -- Zero offsets request the event's base classroom destination.
        local ok, err = pcall(function()
            carry:FireServer(target, 0, 0, 0, 0, 0, 0)
            didCarry = true
            task.wait(0.085)
            if alive and enabled and revision == generation
                and ownChar == Player.Character and target.Parent == Players
                and not isManualGrabWindow() and not DeathTPIsEscaping
                and hum.Health > 0 then
                AntiTPIntentionalTeleportUntil = os.clock() + 1.5
                ev:FireServer()
                didEvent = true
            end
        end)
        if didCarry then
            task.wait(0.06)
            if not isManualGrabWindow() then
                pcall(function() stop:FireServer() end)
            end
        end
        -- The game may teleport our own avatar instead of the target.
        -- Attempt one return only for a large displaced own position.
        pcall(function()
            if didEvent and Player.Character == ownChar and root.Parent
                and (root.Position - originalPosition.Position).Magnitude > 18 then
                ownChar:PivotTo(originalPosition)
            end
        end)
        if alive and enabled and revision == generation then
            if ok and didEvent then
                attempts += 1
                render("Hit by " .. target.Name ..
                    ": classroom TP requested (server decides outcome).")
            else
                render("Counter interrupted." .. (not ok and tostring(err) or ""))
            end
        end
        finish()
    end

    local function detach()
        if damageConn then damageConn:Disconnect() damageConn = nil end
    end
    local function attach(character, revision)
        detach()
        if not character or not enabled or not alive then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 8)
        if not hum or not enabled or not alive or revision ~= generation
            or Player.Character ~= character then return end
        local previousHealth = hum.Health
        damageConn = hum.HealthChanged:Connect(function(health)
            local damage = previousHealth - health
            previousHealth = health
            if not alive or not enabled or revision ~= generation
                or hum.Health <= 0 or damage < 0.01 then return end
            local now = os.clock()
            if now - lastHitAt < 0.12 then return end
            lastHitAt = now
            if busy or isManualGrabWindow() or DeathTPIsEscaping
                or SharedTeleportOwner ~= nil or now < SharedTeleportCooldownUntil
                or now - lastAttemptAt < GLOBAL_COOLDOWN then return end
            local root = character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local target, reason = findAttacker(hum, root)
            if not target then
                render("Damage observed but " .. reason .. "; no TP sent.")
                return
            end
            if now - (perTarget[target.UserId] or -math.huge) < TARGET_COOLDOWN then
                return
            end
            perTarget[target.UserId], lastAttemptAt = now, now
            busy, SharedTeleportOwner = true, "CounterTP"
            render(("Damage %.1f: checking %s (%s).")
                :format(damage, target.Name, reason))
            task.spawn(sendCounter, target, character, revision)
        end)
        render("ON. Watching for health loss within " .. radius .. " studs.")
    end

    persistentToggle(button, function()
        enabled = not enabled
        generation += 1
        detach()
        if enabled then
            if not remotes() then
                enabled = false
                render("OFF. Compatible Carry / EventTeleport remotes missing.")
                return
            end
            render("ON. Wait for a real hit; no bubble is created.")
            if Player.Character then task.spawn(attach, Player.Character, generation) end
        else
            render("OFF. Counter requests disabled.")
        end
    end)
    bindGlobal(Player.CharacterAdded, function(c)
        if enabled then
            generation += 1
            task.spawn(attach, c, generation)
        end
    end)
    bindGlobal(Players.PlayerRemoving, function(p)
        perTarget[p.UserId] = nil
    end)
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        generation += 1
        detach()
        if SharedTeleportOwner == "CounterTP" then SharedTeleportOwner = nil end
        table.clear(perTarget)
    end)
    render()
end

-- ============================================================================
-- VOID HUB V1 / UNIFIED COMMAND CENTER LAYOUT
-- Visual organization only. Every original feature instance, callback, setting,
-- permission check, and server-request workflow remains unchanged.
-- This final pass runs after every feature is created, including TP Push.
-- ============================================================================
do
    local ink = Color3.fromRGB(24, 27, 33) -- high-contrast ink on matte cards
    local muted = Color3.fromRGB(174, 181, 191) -- labels on graphite
    local accent = Color3.fromRGB(248, 249, 252) -- soft silver-white highlight
    local lineColor = Color3.fromRGB(184, 191, 202) -- refined card edges
    local pale = Color3.fromRGB(27, 30, 36) -- graphite navigation
    local white = Color3.fromRGB(255, 255, 255)
    local pageWidth = 880

    -- Keep the established VoidHubV1 title, edition V1, and 70% default size.
    Main.BackgroundColor3 = Color3.fromRGB(16, 18, 23)
    Main.ZIndex = 4
    local mainGradient = Instance.new("UIGradient")
    mainGradient.Name = "MonochromeBackground"
    mainGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 10, 14)),
        ColorSequenceKeypoint.new(0.53, Color3.fromRGB(24, 27, 33)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(11, 12, 16))})
    mainGradient.Rotation = 107
    mainGradient.Parent = Main

    -- Brushed-metal micro-lines remain in the empty top header, not over controls.
    local headerTexture = Instance.new("Frame")
    headerTexture.Name = "SubtleHeaderTexture"
    headerTexture.Position = UDim2.fromOffset(240, 9)
    headerTexture.Size = UDim2.fromOffset(380, 32)
    headerTexture.BackgroundTransparency = 1
    headerTexture.BorderSizePixel = 0
    headerTexture.Active = false
    headerTexture.ZIndex = 1
    headerTexture.Parent = Main
    for i = 1, 15 do
        local grain = Instance.new("Frame")
        grain.Name = "Grain"
        grain.Position = UDim2.fromOffset(i * 24, 0)
        grain.Size = UDim2.fromOffset(1, 31)
        grain.BackgroundColor3 = Color3.fromRGB(250, 251, 255)
        grain.BackgroundTransparency = 0.955
        grain.BorderSizePixel = 0
        grain.Active = false
        grain.Parent = headerTexture
    end

    -- White layered halo around the dark hub; purely visual/non-interactive.
    local function addHalo(name, width, height, alpha, layer, radius)
        local f = Instance.new("Frame")
        f.Name = name
        f.AnchorPoint = Vector2.new(0.5, 0.5)
        f.Position = UDim2.fromScale(0.5, 0.5)
        f.Size = UDim2.fromOffset(width, height)
        f.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        f.BackgroundTransparency = alpha
        f.BorderSizePixel = 0
        f.Active = false
        f.ZIndex = layer
        f.Parent = Holder
        corner(f, radius)
        return f
    end
    addHalo("WhiteGlowSoft", 970, 640, 0.965, 1, 22)
    addHalo("WhiteGlowMid", 956, 626, 0.91, 2, 18)
    addHalo("WhiteGlowInner", 946, 616, 0.78, 3, 15)

    local mainStroke = Main:FindFirstChildOfClass("UIStroke")
    if mainStroke then
        mainStroke.Color = Color3.fromRGB(255, 255, 255)
        mainStroke.Thickness = 1.5
        mainStroke.Transparency = 0.24
    end
    Title.TextColor3 = white
    Title.Font = Enum.Font.GothamBlack
    Title.TextSize = 23

    SizeIndicator.TextColor3 = white
    for _, name in ipairs({"KillBtn", "HidePanel", "SizeDown", "SizeUp"}) do
        local btn = Main:FindFirstChild(name)
        if btn and btn:IsA("TextButton") then
            btn.BackgroundColor3 = Color3.fromRGB(37, 38, 43)
            btn.TextColor3 = white
            local trim = btn:FindFirstChildOfClass("UIStroke")
            if not trim then
                trim = Instance.new("UIStroke")
                trim.Parent = btn
            end
            trim.Name = "WhiteEdge"
            trim.Color = Color3.fromRGB(232, 232, 239)
            trim.Thickness = 1
            trim.Transparency = 0.53
        end
    end
    local editionLabel = Main:FindFirstChild("Edition")
    if editionLabel then
        editionLabel.Text = "V1"
        editionLabel.TextColor3 = accent
        editionLabel.Font = Enum.Font.GothamBold
    end
    local topDivider = Main:FindFirstChild("TopDivider")
    if topDivider then
        topDivider.BackgroundColor3 = accent
        topDivider.BackgroundTransparency = 0.52
        topDivider.Size = UDim2.fromOffset(900, 2)
    end

    local workspaceCaption = Instance.new("TextLabel")
    workspaceCaption.Name = "CommandCenterCaption"
    workspaceCaption.Position = UDim2.fromOffset(400, 15)
    workspaceCaption.Size = UDim2.fromOffset(231, 24)
    workspaceCaption.BackgroundTransparency = 1
    workspaceCaption.Font = Enum.Font.GothamBold
    workspaceCaption.Text = "VOID  /  COMMAND CENTER"
    workspaceCaption.TextSize = 11
    workspaceCaption.TextXAlignment = Enum.TextXAlignment.Right
    workspaceCaption.TextColor3 = muted
    workspaceCaption.Parent = Main

    local displayNames = {
        Defense = "DEFENSE",
        Attack = "ATTACK",
        Movement = "MOVEMENT",
        Visual = "VISUALS",
        Abuse = "MONITOR",
    }
    for name, button in pairs(segmentButtons) do
        button.Text = displayNames[name] or name
        button.TextSize = 12
        button.Font = Enum.Font.GothamBold
        local tabFinish = Instance.new("UIGradient")
        tabFinish.Name = "PremiumTabFinish"
        tabFinish.Color = ColorSequence.new(
            Color3.fromRGB(255, 255, 255), Color3.fromRGB(212, 216, 224))
        tabFinish.Rotation = 90
        tabFinish.Parent = button
        local round = button:FindFirstChildOfClass("UICorner")
        if round then round.CornerRadius = UDim.new(0, 10) end
        local outline = Instance.new("UIStroke")
        outline.Name = "WhiteGlowTabStroke"
        outline.Color = white
        outline.Thickness = 1.4
        outline.Transparency = 0.70
        outline.Parent = button
    end

    local function cleanOldLayout(page)
        -- Decorative elements from the previous pass are rebuilt below.
        -- Never destroy a feature card or any control inside it.
        for _, child in ipairs(page:GetChildren()) do
            local n = child.Name
            if n == "AttackQuickNavigation" or n == "SectionDivider"
                or n == "HelpInfo" or n == "PushForcefieldHeading"
                or n == "PushForcefieldDivider" or n == "Freeze3Header"
                or n:sub(1, 8) == "Section_" then
                child:Destroy()
            end
        end
    end

    local function findCard(page, id, exactTitle)
        local direct = id and page:FindFirstChild(id)
        if direct and direct:IsA("GuiObject") then return direct end
        if exactTitle then
            for _, candidate in ipairs(page:GetChildren()) do
                if candidate:IsA("Frame") then
                    local titleLabel = candidate:FindFirstChildOfClass("TextLabel")
                    if titleLabel and titleLabel.Text == exactTitle then
                        return candidate
                    end
                end
            end
        end
        return nil
    end

    local function polishCard(card)
        if not card or not card:IsA("Frame") then return end
        card.BackgroundColor3 = Color3.fromRGB(248, 249, 251)
        card.BackgroundTransparency = 0
        card.BorderSizePixel = 0
        local rounded = card:FindFirstChildOfClass("UICorner")
        if rounded then
            rounded.CornerRadius = UDim.new(0, 14)
        else
            corner(card, 14)
        end
        local frameStroke = card:FindFirstChildOfClass("UIStroke")
        if frameStroke then
            frameStroke.Color = lineColor
            frameStroke.Thickness = 1.1
            frameStroke.Transparency = 0.25
        else
            local edge = stroke(card, lineColor, 1)
            edge.Transparency = 0.25
        end
        if not card:FindFirstChild("MatteCardFinish") then
            local finish = Instance.new("UIGradient")
            finish.Name = "MatteCardFinish"
            finish.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
                ColorSequenceKeypoint.new(0.6, Color3.fromRGB(249, 250, 252)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(227, 231, 237))})
            finish.Rotation = 92
            finish.Parent = card
            local sheen = Instance.new("Frame")
            sheen.Name = "CardTopSheen"
            sheen.Position = UDim2.fromOffset(16, 1)
            sheen.Size = UDim2.new(1, -32, 0, 1)
            sheen.BackgroundColor3 = white
            sheen.BackgroundTransparency = 0.58
            sheen.BorderSizePixel = 0
            sheen.Active = false
            sheen.Parent = card
        end
        local heading = card:FindFirstChildOfClass("TextLabel")
        if heading and heading.Size.Y.Offset <= 30 then
            heading.TextColor3 = ink
        end
    end

    local function place(page, id, titleText, x, y)
        local item = findCard(page, id, titleText)
        if not item then return 0, nil end
        item.Visible = true
        item.Position = UDim2.fromOffset(x, y)
        if item:IsA("Frame") then polishCard(item) end
        return math.max(0, item.Size.Y.Offset), item
    end

    local function placePair(page, leftId, leftTitle, rightId, rightTitle, y)
        local leftHeight, leftCard = place(page, leftId, leftTitle, 0, y)
        -- FIX: TP Walk and No Slow are 520px wide. The old x=450
        -- overlapped Follow and Walk Speed by 70px; move narrow cards to x=538.
        local rightX = (leftCard and leftCard.Size.X.Offset > 450) and 538 or 450
        local rightHeight = place(page, rightId, rightTitle, rightX, y)
        return y + math.max(leftHeight, rightHeight, 0) + 16
    end

    local function addSection(page, jumpPoints, quickName, text, y)
        jumpPoints[#jumpPoints + 1] = {label = quickName, scrollY = math.max(0, y - 6)}

        local ribbon = Instance.new("Frame")
        ribbon.Name = "V1SectionRibbon"
        ribbon.Position = UDim2.fromOffset(0, y)
        ribbon.Size = UDim2.fromOffset(pageWidth, 34)
        ribbon.BackgroundColor3 = Color3.fromRGB(33, 36, 43)
        ribbon.BackgroundTransparency = 0.18
        ribbon.BorderSizePixel = 0
        ribbon.Active = false
        ribbon.Parent = page
        corner(ribbon, 8)
        local ribbonFinish = Instance.new("UIGradient")
        ribbonFinish.Color = ColorSequence.new(
            Color3.fromRGB(42, 46, 54), Color3.fromRGB(17, 19, 24))
        ribbonFinish.Rotation = 0
        ribbonFinish.Parent = ribbon

        local leftRule = Instance.new("Frame")
        leftRule.Name = "V1SectionAccent"
        leftRule.Position = UDim2.fromOffset(1, y + 5)
        leftRule.Size = UDim2.fromOffset(4, 20)
        leftRule.BackgroundColor3 = accent
        leftRule.BorderSizePixel = 0
        leftRule.Parent = page
        corner(leftRule, 2)

        local label = Instance.new("TextLabel")
        label.Name = "V1SectionTitle"
        label.Position = UDim2.fromOffset(16, y + 2)
        label.Size = UDim2.fromOffset(845, 27)
        label.BackgroundTransparency = 1
        label.Text = text
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.TextColor3 = white
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = page

        local line = Instance.new("Frame")
        line.Name = "V1SectionLine"
        line.Position = UDim2.fromOffset(0, y + 33)
        line.Size = UDim2.fromOffset(pageWidth, 1)
        line.BackgroundColor3 = Color3.fromRGB(88, 93, 105)
        line.BackgroundTransparency = 0.57
        line.BorderSizePixel = 0
        line.Parent = page
        return y + 50
    end

    local function newNavigation(page, caption, subtitle, items)
        local bar = Instance.new("Frame")
        bar.Name = "V1QuickNavigation_" .. page.Name
        bar.Position = UDim2.fromOffset(0, 0)
        bar.Size = UDim2.fromOffset(pageWidth, 78)
        bar.BackgroundColor3 = pale
        bar.BorderSizePixel = 0
        bar.ZIndex = 25
        bar.Visible = false
        bar.Parent = Content -- shortcuts remain visible when the page scrolls
        corner(bar, 12)
        local barFinish = Instance.new("UIGradient")
        barFinish.Name = "QuickNavMatteFinish"
        barFinish.Color = ColorSequence.new(
            Color3.fromRGB(44, 48, 56), Color3.fromRGB(17, 19, 24))
        barFinish.Rotation = 90
        barFinish.Parent = bar
        local barOutline = Instance.new("UIStroke")
        barOutline.Color = white
        barOutline.Thickness = 1.0
        barOutline.Transparency = 0.54
        barOutline.Parent = bar

        local head = Instance.new("TextLabel")
        head.Name = "NavigationTitle"
        head.Position = UDim2.fromOffset(14, 5)
        head.Size = UDim2.fromOffset(290, 22)
        head.BackgroundTransparency = 1
        head.Font = Enum.Font.GothamBlack
        head.TextColor3 = white
        head.TextSize = 15
        head.Text = caption
        head.ZIndex = 26
        head.TextXAlignment = Enum.TextXAlignment.Left
        head.Parent = bar

        local sub = Instance.new("TextLabel")
        sub.Name = "NavigationSubtitle"
        sub.Position = UDim2.fromOffset(310, 5)
        sub.Size = UDim2.fromOffset(555, 22)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.TextColor3 = Color3.fromRGB(197, 197, 204)
        sub.TextSize = 11
        sub.Text = subtitle
        sub.ZIndex = 26
        sub.TextXAlignment = Enum.TextXAlignment.Right
        sub.Parent = bar

        local total = math.max(1, #items)
        local gap = 8
        local buttonWidth = math.floor((pageWidth - 28 - gap * (total - 1)) / total)
        local navButtons = {}
        for i, item in ipairs(items) do
            local button = Instance.new("TextButton")
            button.Name = "QuickGo" .. tostring(i)
            button.Position = UDim2.fromOffset(14 + (i - 1) * (buttonWidth + gap), 36)
            button.Size = UDim2.fromOffset(buttonWidth, 31)
            button.BackgroundColor3 = Color3.fromRGB(47, 48, 54)
            button.TextColor3 = white
            button.Text = item.label
            button.TextSize = 12
            button.Font = Enum.Font.GothamBold
            button.AutoButtonColor = false
            button.ZIndex = 26
            button.Parent = bar
            navButtons[i] = button
            corner(button, 8)
            local border = Instance.new("UIStroke")
            border.Color = white
            border.Transparency = 0.72
            border.Thickness = 1
            border.Parent = button
            button.MouseEnter:Connect(function()
                if not button:GetAttribute("IsCurrentSection") then
                    TweenService:Create(button, TweenInfo.new(0.14), {
                        BackgroundColor3 = Color3.fromRGB(83, 87, 97)
                    }):Play()
                end
            end)
            button.MouseLeave:Connect(function()
                if not button:GetAttribute("IsCurrentSection") then
                    TweenService:Create(button, TweenInfo.new(0.14), {
                        BackgroundColor3 = Color3.fromRGB(47, 48, 54)
                    }):Play()
                end
            end)
            -- FIX: scroll destinations account for the fixed 78px shortcut bar.
            local destination = math.max(0, item.scrollY - 86)
            button.Activated:Connect(function()
                -- Scroll only the corresponding page. Never touch feature state.
                local maxScroll = math.max(0, page.CanvasSize.Y.Offset - page.AbsoluteSize.Y)
                page.CanvasPosition = Vector2.new(0, math.clamp(destination, 0, maxScroll))
            end)
        end

        -- Light active shortcut gives a clear "you are here" indication.
        local currentShortcut = 0
        local function syncQuickNavigation()
            local visibleTop = page.CanvasPosition.Y + 108
            local selected = 1
            for index, jump in ipairs(items) do
                if visibleTop >= jump.scrollY then selected = index end
            end
            if selected == currentShortcut then return end
            currentShortcut = selected
            for index, button in ipairs(navButtons) do
                local isCurrent = index == selected
                button:SetAttribute("IsCurrentSection", isCurrent)
                button.BackgroundColor3 = isCurrent
                    and Color3.fromRGB(244, 247, 251)
                    or Color3.fromRGB(47, 48, 54)
                button.TextColor3 = isCurrent
                    and Color3.fromRGB(19, 21, 26)
                    or Color3.fromRGB(245, 246, 249)
                local edge = button:FindFirstChildOfClass("UIStroke")
                if edge then edge.Transparency = isCurrent and 0.12 or 0.75 end
            end
        end
        page:GetPropertyChangedSignal("CanvasPosition"):Connect(syncQuickNavigation)
        syncQuickNavigation()
    end

    local function finishPage(page, bottom, caption, subtitle, jumps)
        page.CanvasSize = UDim2.fromOffset(0, math.max(490, bottom + 28))
        page.ScrollBarThickness = 6
        page.ScrollBarImageColor3 = Color3.fromRGB(166, 173, 184)
        page.ScrollingDirection = Enum.ScrollingDirection.Y
        page.CanvasPosition = Vector2.new(0, 0)
        newNavigation(page, caption, subtitle, jumps)
    end

    -- DEFENSE: most-used immediate guard first, then physical recovery.
    do
        local p = pages["Defense"]
        cleanOldLayout(p)
        local heading = p:FindFirstChild("DefenseHeading")
        if heading then heading:Destroy() end
        local nav = {}
        local y = 90
        -- Counter TP has its OWN main tab, separate from Forcefield/Defense.
        y = addSection(p, nav, "AUTO BLOCK", "01   AUTOMATIC & MANUAL GUARD", y)
        y = y + place(p, "DefenseAutoBlock", nil, 0, y) + 20
        y = addSection(p, nav, "GRAB / RAGDOLL", "02   GRAB & RAGDOLL PROTECTION", y)
        y = placePair(p, "DefenseAntiGrab", nil, "DefenseAntiRagdoll", nil, y) + 10
        y = addSection(p, nav, "RECOVERY", "03   FALL SAFETY & RESPAWN", y)
        y = placePair(p, "DefenseAntiVoid", nil, "DefenseDeathTP", nil, y) + 10
        y = addSection(p, nav, "ANTI TP", "04   TELEPORT PROTECTION", y)
        y = y + place(p, "DefenseAntiTP", nil, 0, y)
        finishPage(p, y, "DEFENSE", "Guard, recovery and anti-teleport controls", nav)
    end

    -- MOVEMENT: everyday walking controls before advanced movement.
    do
        local p = pages["Movement"]
        cleanOldLayout(p)
        local nav = {}
        local y = 90
        y = addSection(p, nav, "SPEED", "01   WALKING & ANTI-SLOW", y)
        y = placePair(p, "MovementNoSlow", nil, "MovementWalkSpeed", nil, y) + 10
        y = addSection(p, nav, "FOLLOW / TP", "02   FOLLOW & TP WALK", y)
        y = placePair(p, nil, "TP Walk", "MovementFollow", nil, y) + 10
        y = addSection(p, nav, "ORBIT", "03   ORBITAL PLAYER", y)
        y = y + place(p, "MovementOrbitalPlayer", nil, 0, y) + 20
        y = addSection(p, nav, "ANNOUNCE", "04   ANNOUNCEMENTS", y)
        y = y + place(p, "MovementAnnouncement", nil, 0, y)
        finishPage(p, y, "MOVEMENT", "Everyday movement, teleport and orbit", nav)
    end

    -- ATTACK: Forcefield is immediately visible and the old quick-jump
    -- coordinates are replaced with live section destinations.
    do
        local p = pages["Attack"]
        cleanOldLayout(p)
        local nav = {}
        local y = 90

        -- Forcefield and Counter TP share ONE visible row in Attack.
        -- They are two genuinely independent frames, toggles, and actions.
        -- Important: both original 880px cards had controls at x=450+,
        -- so merely placing them beside each other cut off APPLY/status.
        -- Reflow all controls within two separate 430px cards.
        y = addSection(p, nav, "PUSH + COUNTER", "01   FORCEFIELD + COUNTER TP  |  SIDE BY SIDE", y)
        local leftHeight, forceCard = place(p, "AttackPushForcefield", nil, 0, y)
        local rightHeight, counterCard = place(p, "AttackCounterTP", nil, 450, y)

        local function compactAttackCard(card, kind)
            if not card then return end
            card.Visible = true
            card.Size = UDim2.fromOffset(430, 220)
            local heading = card:FindFirstChildOfClass("TextLabel")
            if heading then
                heading.Position = UDim2.fromOffset(16, 12)
                heading.Size = UDim2.fromOffset(397, 24)
                heading.TextSize = 15
                heading.TextXAlignment = Enum.TextXAlignment.Left
            end
            local function move(name, x, yPos, w, h, textSize)
                local item = card:FindFirstChild(name)
                if item and item:IsA("GuiObject") then
                    item.Position = UDim2.fromOffset(x, yPos)
                    item.Size = UDim2.fromOffset(w, h)
                    if textSize and item:IsA("TextLabel") then
                        item.TextSize = textSize
                    end
                end
            end
            if kind == "force" then
                move("ForcefieldToggle", 16, 49, 182, 36)
                move("ForcefieldRadiusLabel", 204, 49, 116, 36, 11)
                move("ForcefieldRadius", 325, 49, 87, 36)
                move("ForcefieldApply", 16, 105, 115, 36)
                move("ForcefieldStatus", 146, 101, 265, 108, 11)
            else
                move("CounterTPToggle", 16, 49, 182, 36)
                move("CounterTPRadiusLabel", 204, 49, 116, 36, 11)
                move("CounterTPRadius", 325, 49, 87, 36)
                move("CounterTPApply", 16, 105, 115, 36)
                move("CounterTPStatus", 146, 101, 265, 108, 11)
            end
        end
        compactAttackCard(forceCard, "force")
        compactAttackCard(counterCard, "counter")
        if not forceCard or not counterCard then
            warn("[VOID HUB] Side-by-side Attack cards not created; check script version.")
        end
        y = y + 220 + 22

        y = addSection(p, nav, "COMBAT", "02   COMBAT & ANIMATIONS", y)
        y = y + place(p, "AttackKillAuraTest", nil, 0, y) + 16
        y = y + place(p, "AttackPlayerHitboxes", nil, 0, y) + 16
        y = y + place(p, "AttackNoHitAnims", nil, 0, y) + 20

        y = addSection(p, nav, "PLAYER LISTS", "03   WHITELIST & BLACKLIST", y)
        y = y + place(p, "PlayerListsCombined", nil, 0, y) + 6
        local listHint = p:FindFirstChild("SharedListInfo")
        if listHint and listHint:IsA("TextLabel") then
            listHint.Position = UDim2.fromOffset(12, y)
            listHint.Size = UDim2.fromOffset(855, 44)
            listHint.TextColor3 = muted
            listHint.TextWrapped = true
            y = y + 55
        end

        y = addSection(p, nav, "BRING", "04   CARRY & TELEPORT TOOLS", y)
        y = y + place(p, "AttackCarryControl", nil, 0, y) + 22

        y = addSection(p, nav, "FREEZE / TOOLS", "05   FREEZE & REQUEST MANAGEMENT", y)
        local serverHeight = place(p, "OwnerFreeze30Card", nil, 0, y)
        if serverHeight > 0 then y = y + serverHeight + 17 end

        local hDecline = place(p, "OriginalDecline", nil, 0, y)
        local hAccept = place(p, "OriginalAccept", nil, 450, y)
        local hasLegacy = hDecline > 0 or hAccept > 0
        if hasLegacy then
            y = y + math.max(hDecline, hAccept) + 16
            y = placePair(p, "OriginalDeclineRequests", nil, "OriginalSpamCarry", nil, y)
            y = y + place(p, "OriginalStats", nil, 0, y) + 10

            -- Retain the original informational note, but keep it in the correct section.
            for _, child in ipairs(p:GetChildren()) do
                if child:IsA("TextLabel")
                    and child.Text:find("FREEZE uses the combined lists above", 1, true) then
                    child.Position = UDim2.fromOffset(12, y)
                    child.Size = UDim2.fromOffset(854, 68)
                    child.TextWrapped = true
                    child.TextColor3 = muted
                    y = y + 73
                    break
                end
            end

            y = y + place(p, "Freeze100Monitor", nil, 0, y) + 15
        end
        if not hasLegacy and serverHeight == 0 then
            local notice = Instance.new("TextLabel")
            notice.Name = "FreezeAvailabilityNotice"
            notice.Position = UDim2.fromOffset(16, y + 4)
            notice.Size = UDim2.fromOffset(834, 52)
            notice.BackgroundTransparency = 1
            notice.Text = "Freeze and carry controls appear when the game's supported services are available."
            notice.TextWrapped = true
            notice.Font = Enum.Font.Gotham
            notice.TextColor3 = muted
            notice.TextSize = 12
            notice.Parent = p
            y = y + 64
        end
        finishPage(p, y, "ATTACK", "Quick access to combat, targets and carry tools", nav)
    end

    -- VISUALS: side-by-side overlays followed by player-health tools.
    do
        local p = pages["Visual"]
        cleanOldLayout(p)
        local nav = {}
        local y = 90
        y = addSection(p, nav, "OVERLAYS", "01   SCREEN OVERLAYS", y)
        local hEsp = place(p, nil, "ESP", 0, y)
        local hTracer = place(p, nil, "Tracers", 450, y)
        y = y + math.max(hEsp, hTracer, 90) + 22
        y = addSection(p, nav, "HEALTH BARS", "02   PLAYER HEALTH", y)
        local healthHeight = place(p, nil, "Health Bars", 0, y)
        local help = Instance.new("Frame")
        help.Name = "VisualHelpInfo"
        help.Position = UDim2.fromOffset(450, y)
        help.Size = UDim2.fromOffset(430, math.max(healthHeight, 142))
        help.BackgroundColor3 = pale
        help.BorderSizePixel = 0
        help.Parent = p
        corner(help, 12)
        local description = Instance.new("TextLabel")
        description.Name = "VisualHelpText"
        description.Position = UDim2.fromOffset(17, 16)
        description.Size = UDim2.new(1, -34, 1, -32)
        description.BackgroundTransparency = 1
        description.Font = Enum.Font.Gotham
        description.TextSize = 12
        description.TextWrapped = true
        description.TextXAlignment = Enum.TextXAlignment.Left
        description.TextYAlignment = Enum.TextYAlignment.Top
        description.TextColor3 = muted
        description.Text = "ESP highlights players. Tracers show direction lines. Health Bars display replicated health. You can set overlay keybinds next to their toggles."
        description.Parent = help
        y = y + math.max(healthHeight, 142)
        finishPage(p, y, "VISUALS", "Information overlays and useful keybinds", nav)
    end

    -- MONITOR: keep its live player rows, clear-alert button and event cards
    -- in their existing coordinates so monitoring callbacks remain valid.
    do
        local p = pages["Abuse"]
        cleanOldLayout(p)
        p.ScrollBarImageColor3 = Color3.fromRGB(150, 166, 194)
        p.ScrollBarThickness = 6
        local heading = p:FindFirstChild("AbuseHeading")
        if heading then
            heading.Text = "PLAYER ACTIVITY MONITOR"
            heading.Font = Enum.Font.GothamBlack
            heading.TextColor3 = white
        end
        for _, child in ipairs(p:GetChildren()) do
            if child:IsA("Frame") and child.Name ~= "tracerCanvas" then
                polishCard(child)
            end
        end
        p.CanvasPosition = Vector2.new(0, 0)
    end

    -- Harmonize input text and corners without altering stateful button colors
    -- or modifying any feature callback/remote.
    for _, descendant in ipairs(Main:GetDescendants()) do
        if descendant:IsA("TextBox") then
            descendant.PlaceholderColor3 = muted
            if descendant.BackgroundTransparency < 1 then
                descendant.BackgroundColor3 = Color3.fromRGB(241, 243, 246)
                local rounded = descendant:FindFirstChildOfClass("UICorner")
                if not rounded then corner(descendant, 8) end
            end
        elseif descendant:IsA("ScrollingFrame") then
            descendant.ScrollBarImageColor3 = Color3.fromRGB(162, 169, 180)
            descendant.ScrollBarThickness = math.max(5, descendant.ScrollBarThickness)
        end
    end
end

finishPersistentRestore(Main)
setSegment(type(savedUI.misc.lastTab) == "string" and segmentButtons[savedUI.misc.lastTab]
    and savedUI.misc.lastTab or "Defense")
setPanel(true)
updatePanelScale()
print("[VOID HUB] Settings restored: " ..
    (diskSaveAvailable and "local file" or "current session only"))
-- Give the final GUI a rendered frame before letting the intro close.
task.defer(function()
    if not Gui.Parent then return end
    RunService.Heartbeat:Wait()
    if not Gui.Parent then return end
    guiFullyLoaded = true
    print("[VOID HUB V1] All GUI sections ready; intro may now fade.")
end)
print("[VOID HUB V57] Freeze targets filtered by Blacklist; Whitelist protected. LeftCtrl or V toggles")
