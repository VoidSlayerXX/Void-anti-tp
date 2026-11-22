-- ATTACK: FORCEFIELD (V181 WORKING NOV 14 TP PUSH + SELF PROTECTION)
-- Uses the same CarryRequest -> EventTeleportEvent -> StopCarry workflow
-- as the existing manual Bring, with a nearby offset target.
-- Server authority determines if a remote request changes the target position.
-- Sequential, rate-limited retries while any player remains close, including stationary players.
-- Faster remote handoff; position return only corrects real teleports.
-- Does not teleport our character to follow the target.
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
        heading.Text = "05    MULTI-PLAYER TP FORCEFIELD"
        heading.Parent = page

        local divider = Instance.new("Frame")
        divider.Name = "PushForcefieldDivider"
        divider.Position = UDim2.fromOffset(2, headingY + 29)
        divider.Size = UDim2.fromOffset(876, 1)
        divider.BackgroundColor3 = Color3.fromRGB(219, 225, 237)
        divider.BorderSizePixel = 0
        divider.Parent = page

        local cardY = headingY + 40
        local card = makeFeatureCard(page, "Multi-Player TP Push  |  Bubble Radius", cardY)
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
        radiusInput.PlaceholderText = "3-15"
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
        local lastTargetRequest = {}
        local lastRequestAt = -math.huge
        local nearbyCount = 0
        local scanAccumulator = 0
        local SCAN_INTERVAL = 0.045 -- checks at approximately 22Hz
        local bubbleFlashUntil = 0
        local returnHoldConnection = nil
        local returnHoldVisualConnection = nil
        local safetyStop = false
        local mapSnapCount = 0
        local lastMapSnapAt = -math.huge
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
            -- Keep the local avatar at the precise position/rotation from
            -- immediately before the carry sequence, without anchoring it.
            -- Heartbeat handles physics; RenderStepped reduces visible jumping.
            stopOwnPositionHold()
            local since = os.clock()
            local function maintainPosition()
                if not enabled or not alive or not Gui.Parent
                    or Player.Character ~= ownChar or DeathTPIsEscaping
                    or os.clock() - since >= duration then
                    stopOwnPositionHold()
                    return
                end
                local hrp = ownChar:FindFirstChild("HumanoidRootPart")
                local hum = ownChar:FindFirstChildOfClass("Humanoid")
                if not hrp or not hrp.Parent or not hum or hum.Health <= 0 then
                    stopOwnPositionHold()
                    return
                end
                -- Heartbeat/RenderStepped hold on OUR avatar only.
                -- The engine/server remains authoritative for true physics.
                local drift = (hrp.Position - saved.Position).Magnitude
                local now = os.clock()
                if drift > 70 then
                    if now - lastMapSnapAt > 1.5 then mapSnapCount = 0 end
                    mapSnapCount += 1
                    lastMapSnapAt = now
                    if mapSnapCount >= 3 then safetyStop = true end
                end
                hum.Jump = false
                if drift > 0.025
                    or (hrp.CFrame.LookVector - saved.LookVector).Magnitude > 0.01 then
                    hrp.CFrame = saved
                end
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end
            returnHoldConnection = RunService.Heartbeat:Connect(maintainPosition)
            returnHoldVisualConnection = RunService.RenderStepped:Connect(maintainPosition)
            maintainPosition()
        end
        local note = "OFF. Repeated TP-style push attempts while players remain near your bubble."
        -- Restore the last stable cadence: zero cooldown previously caused
        -- the carry event to race ahead of the game server.
        local GLOBAL_COOLDOWN = 0.45
        local TARGET_COOLDOWN = 1.15
        local EDGE_TOLERANCE = 0.85 -- characters touching the bubble count even if root is just outside
        local PUSH_EXTRA_STUDS = 8 -- land 8 studs outside the chosen bubble radius
        local EVENT_POSITION = Vector3.new(53.5, 8.298911, 118.149994)

        local function showState(nextNote)
            if nextNote then note = nextNote end
            if not alive or not Gui.Parent then return end
            toggle.Text = enabled and "FORCEFIELD: ON" or "FORCEFIELD: OFF"
            animateToggle(toggle, enabled)
            info.Text = ("%s\nRadius: %d studs | Inside: %d | Push attempts: %d | +%d studs outside.")
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
            part.Material = Enum.Material.ForceField
            part.Color = Color3.fromRGB(229, 240, 255)
            part.Transparency = 0.76
            part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
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
            scanAccumulator = 0
            if enabled then
                safetyStop = false
                mapSnapCount = 0
                lastMapSnapAt = -math.huge
                local carry = validRemotes()
                if not carry then
                    enabled = false
                    showState("Game Bring/Carry remotes unavailable. No TP push possible here.")
                    return
                end
                makeBubble()
                showState("ON. Rechecks idle and moving players nearby; retries individually with cooldowns.")
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
            if not carry then
                finish()
                showState("Bring remotes missing. Can't request TP push.")
                return
            end
            local ownChar = Player.Character
            local root = ownChar and ownChar:FindFirstChild("HumanoidRootPart")
            local human = ownChar and ownChar:FindFirstChildOfClass("Humanoid")
            if not root or not human or human.Health <= 0
                or safetyStop or isManualGrabWindow()
                or Gui:GetAttribute("AntiGrabRecovering") == true then
                finish()
                return
            end
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
                if alive and enabled and not safetyStop
                    and target.Parent == Players and Player.Character == ownChar
                    and human.Health > 0 and not isManualGrabWindow()
                    and Gui:GetAttribute("AntiGrabRecovering") ~= true then
                    event:FireServer()
                    eventSent = true
                end
            end)
            -- EventTeleportEvent may reposition our avatar; restore it immediately.
            pcall(function()
                if Player.Character == ownChar and root.Parent then
                    root.CFrame = saved
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end
            end)
            if carried then
                -- Bring uses a short return hold because server teleport responses
                -- can arrive after the immediate local-position restoration.
                holdOwnPosition(saved, ownChar, 0.60)
                task.wait(0.05)
                if Player.Character == ownChar and not isManualGrabWindow() then
                    pcall(function() stop:FireServer() end)
                end
            else
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
            local nowForVisual = os.clock()
            if nowForVisual < bubbleFlashUntil then
                local fraction = math.clamp((bubbleFlashUntil - nowForVisual) / 0.24, 0, 1)
                bubble.Transparency = 0.76 - 0.18 * fraction
            else
                bubble.Transparency = 0.76
            end
            bubble.CFrame = CFrame.new(root.Position)
            statusClock += math.clamp(tonumber(dt) or 0, 0, 0.1)
            scanAccumulator += math.clamp(tonumber(dt) or 0, 0, 0.1)
            if safetyStop then
                enabled = false
                if SharedTeleportOwner == "Forcefield" then
                    SharedTeleportOwner = nil
                end
                stopOwnPositionHold()
                removeBubble()
                showState("SAFETY STOP: repeated own map teleports; toggle to retry.")
                return
            end
            if scanAccumulator < SCAN_INTERVAL then return end
            scanAccumulator = 0
            local now = os.clock()
            local eligible = {}
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
                        -- HumanoidRootParts can be almost overlapping (especially
                        -- when you walk straight into a player who is idle).
                        -- The body can enter the bubble before its root does.
                        if distance <= radius + EDGE_TOLERANCE then
                            nearbyCount += 1
                            local since = now - (lastTargetRequest[other.UserId] or -math.huge)
                            if since >= TARGET_COOLDOWN then
                                local flat = Vector3.new(relative.X, 0, relative.Z)
                                if flat.Magnitude < 0.15 then
                                    -- Stable fallback for two players with almost
                                    -- identical X/Z positions. Never skip this target.
                                    local look = otherRoot.CFrame.LookVector
                                    flat = Vector3.new(look.X, 0, look.Z)
                                    if flat.Magnitude < 0.05 then flat = Vector3.new(1, 0, 0) end
                                end
                                eligible[#eligible + 1] = {
                                    player = other,
                                    offset = flat,
                                    y = otherRoot.Position.Y,
                                    distance = distance,
                                    since = since,
                                }
                            end
                        end
                    end
                end
            end

            -- Push the nearest threat first. Targets on cooldown are skipped,
            -- so other players get turns instead of being blocked by one player.
            if not busy and #eligible > 0
                and not SharedTeleportOwner and not isManualGrabWindow()
                and Gui:GetAttribute("AntiGrabRecovering") ~= true
                and now >= (tonumber(Gui:GetAttribute("AntiGrabPriorityUntil")) or 0)
                and now >= SharedTeleportCooldownUntil
                and now - lastRequestAt >= GLOBAL_COOLDOWN then
                table.sort(eligible, function(a, b)
                    if a.distance ~= b.distance then return a.distance < b.distance end
                    return a.player.UserId < b.player.UserId
                end)
                local entry = eligible[1]
                local destOffset = entry.offset.Unit * (radius + PUSH_EXTRA_STUDS)
                local desired = Vector3.new(
                    root.Position.X + destOffset.X,
                    entry.y,
                    root.Position.Z + destOffset.Z
                )
                lastRequestAt = now
                lastTargetRequest[entry.player.UserId] = now
                bubbleFlashUntil = now + 0.24
                busy = true
                SharedTeleportOwner = "Forcefield"
                task.spawn(requestTeleportPush, entry.player, desired)
            end

            if statusClock >= 0.6 then
                statusClock = 0
                if not busy then
                    if nearbyCount > 0 then
                        showState("ON. " .. nearbyCount .. " player(s) near bubble. Retrying even if stationary.")
                    else
                        showState("ON. Bubble clear. Watching for approaching players.")
                    end
                end
            end
        end)

        bindGlobal(Players.PlayerRemoving, function(leaving)
            lastTargetRequest[leaving.UserId] = nil
        end)
        Gui.Destroying:Connect(function()
            enabled, alive = false, false
            if SharedTeleportOwner == "Forcefield" then SharedTeleportOwner = nil end
            stopOwnPositionHold()
            removeBubble()
            table.clear(lastTargetRequest)
        end)
        showState()
    end
end

