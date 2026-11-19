-- VOIDHUBV1 COUNTER TP - SAVED MODULE SOURCE (2026-11-19)
-- Archived by request: removed from the main GUI but retained for later restoration.
-- This is an extracted feature block, not a standalone Roblox script: it expects
-- the existing VoidHubV1 locals/functions (Gui, pages, Player, Players, RunService,
-- State, shared teleport guards, render helpers, savedApply, etc.).
-- Restore by inserting the ORIGINAL BLOCK below before the
-- "-- VOID HUB V1 / UNIFIED COMMAND CENTER LAYOUT" section and restoring
-- its Attack page layout placement. Do not execute this file by itself.
-- Original version sourced from main blob a7dddf8c24dcdceb5788b39affe66474073ce7e9.

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
    label.Text = "Radius (1-9):"
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(35, 39, 47)
    label.Parent = card

    local radiusBox = Instance.new("TextBox")
    radiusBox.Name = "CounterTPRadius"
    radiusBox.Position = UDim2.fromOffset(359, 49)
    radiusBox.Size = UDim2.fromOffset(77, 36)
    radiusBox.Text = "9"
    radiusBox.PlaceholderText = "1-9"
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
    local radius, attempts = 9, 0
    local note = "OFF. No proximity trigger; waits for real health loss."
    local lastState, generation, damageConn = nil, 0, nil
    local stateConn, standConn, sampleConn = nil, nil, nil
    local lastDamageAt = -math.huge
    local lastStateHitAt = -math.huge
    local hitQueue = {}
    local queueWorkerRunning = false
    local MAX_HIT_QUEUE = 32
    Gui:SetAttribute("CounterTPHitPending", false)
    local nearTimes = {}
    local hitsDetected = 0
    local ownGuardConnection = nil
    local groundGuardHumanoid, oldJumpAllowed = nil, nil
    local oldAutoRotate = nil
    local function stopOwnGuard()
        if ownGuardConnection then
            ownGuardConnection:Disconnect()
            ownGuardConnection = nil
        end
        -- Restore the character's jump + turning state on OFF, death, or respawn.
        if groundGuardHumanoid and groundGuardHumanoid.Parent then
            pcall(function()
                groundGuardHumanoid:SetStateEnabled(
                    Enum.HumanoidStateType.Jumping, oldJumpAllowed)
                if oldAutoRotate ~= nil then
                    groundGuardHumanoid.AutoRotate = oldAutoRotate
                end
            end)
        end
        groundGuardHumanoid, oldJumpAllowed, oldAutoRotate = nil, nil, nil
    end
    -- Match the proven Forcefield coordinate conversion. Target classroom
    -- destination is separate from the event's origin coordinate.
    local EVENT_POSITION = Vector3.new(53.5, 8.298911, 118.149994)
    local CLASSROOM_POSITION = Vector3.new(52, 4, 120)

    local function render(message)
        if message then note = message end
        if not alive or not Gui.Parent then return end
        if lastState ~= enabled then
            lastState = enabled
            button.Text = enabled and "COUNTER TP: ON" or "COUNTER TP: OFF"
            animateToggle(button, enabled)
        end
        status.Text = ("%s\nRange: %d studs | Hits seen: %d | Requests sent: %d | Queued: %d")
            :format(note, radius, hitsDetected, attempts, #hitQueue)
    end

    local function changeRadius()
        local n = tonumber(radiusBox.Text)
        if not n or n ~= n or n == math.huge or n == -math.huge then
            radiusBox.Text = tostring(radius)
            render("Please enter 1-9 studs.")
            return
        end
        radius = math.clamp(math.floor(n + 0.5), 1, 9)
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
        local now = os.clock()
        local function close(other)
            if not other or other == Player or other.Parent ~= Players
                or inPlayerList(State.Whitelist, other) then return false end
            return nearby(other, root)
                or (nearTimes[other.UserId]
                    and now - nearTimes[other.UserId] <= 0.9)
        end
        local tag = humanoid:FindFirstChild("creator")
        if tag and tag:IsA("ObjectValue") then
            local who = tag.Value
            if who and who:IsA("Player") and close(who) then
                return who, "damage tag"
            end
        end
        local one, count = nil, 0
        for _, other in ipairs(Players:GetPlayers()) do
            if close(other) then
                count += 1
                one = other
                if count > 1 then return nil, "multiple close players" end
            end
        end
        return one, one and "recent 1-9 stud contact" or "nobody within radius"
    end

    local function sendCounter(target, ownChar, revision)
        local function finish()
            if SharedTeleportOwner == "CounterTP" then
                SharedTeleportOwner = nil
                SharedTeleportCooldownUntil = math.max(
                    SharedTeleportCooldownUntil, os.clock() + 0.06)
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
        -- Fixed facing: Counter TP cannot rotate the local character.
        -- Capture a single world-space orientation before CarryRequest.
        local lockedFacing = originalPosition.Rotation
        local lockedLook = originalPosition.LookVector
        local lockedUp = originalPosition.UpVector
        -- Anti-jump/anti-fling works only during a hit counter sequence.
        -- Never anchor the body, create a physical bubble, or PivotTo the rig.
        stopOwnGuard()
        local safePosition = originalPosition
        local previousPosition = root.Position
        local guardStarted = os.clock()
        -- Protect the small CarryRequest handoff too, not only EventTeleportEvent.
        local eventWindowEnds = guardStarted + 0.25
        local correctionCount, lastCorrection = 0, -math.huge
        local floorParams = RaycastParams.new()
        floorParams.FilterType = Enum.RaycastFilterType.Exclude
        floorParams.FilterDescendantsInstances = {ownChar}
        local function floorRootY(position)
            local floor = workspace:Raycast(
                position + Vector3.new(0, 2, 0),
                Vector3.new(0, -11, 0), floorParams)
            if floor and floor.Normal.Y > 0.6 then
                return floor.Position.Y + hum.HipHeight + root.Size.Y * 0.5
            end
            return nil
        end
        groundGuardHumanoid = hum
        oldJumpAllowed = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
        oldAutoRotate = hum.AutoRotate
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
            hum.AutoRotate = false
        end)
        ownGuardConnection = RunService.Heartbeat:Connect(function()
            local now = os.clock()
            if not alive or not enabled or revision ~= generation
                or Player.Character ~= ownChar or not root.Parent
                or hum.Health <= 0 or now - guardStarted > 1.8
                or isManualGrabWindow() or DeathTPIsEscaping then
                stopOwnGuard()
                return
            end
            -- The local jump state and positive Y impulse are the visible bounce.
            hum.Jump = false
            -- Keep the Roblox humanoid from turning toward the target or inputs.
            if hum.AutoRotate then hum.AutoRotate = false end
            local current = root.Position
            local step = current - previousPosition
            local eventActive = now <= eventWindowEnds
            local awayFromSafe = (current - safePosition.Position).Magnitude
            local unnaturalRise = current.Y - safePosition.Position.Y > 1.35
            local teleported = step.Magnitude > 6 or awayFromSafe > 12
            if eventActive and (teleported or unnaturalRise)
                and correctionCount < 3 and now - lastCorrection >= 0.11 then
                local returnPosition = safePosition.Position
                local floorY = floorRootY(returnPosition)
                if floorY and math.abs(floorY - returnPosition.Y) < 3 then
                    returnPosition = Vector3.new(returnPosition.X, floorY, returnPosition.Z)
                end
                local ok = pcall(function()
                    -- Single root-only correction per distinct server impulse.
                    root.CFrame = CFrame.new(returnPosition) * lockedFacing
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
                if not ok then
                    warn("[VOID HUB COUNTER TP] Ground return failed.")
                end
                correctionCount += 1
                lastCorrection = now
                previousPosition = returnPosition
                return
            end
            -- Kill upward knockback and spin; keep ordinary walking responsive.
            local vel = root.AssemblyLinearVelocity
            local sideways = Vector3.new(vel.X, 0, vel.Z)
            if sideways.Magnitude > 18 then
                sideways = sideways.Unit * 18
            end
            local newY = math.min(vel.Y, 0)
            if vel.Y > 0 or (sideways - Vector3.new(vel.X, 0, vel.Z)).Magnitude > 0.01 then
                root.AssemblyLinearVelocity = Vector3.new(sideways.X, newY, sideways.Z)
            end
            -- Suppress even small angular impulses, not only high-speed spin.
            if root.AssemblyAngularVelocity.Magnitude > 0.001 then
                root.AssemblyAngularVelocity = Vector3.zero
            end
            -- Position stays unchanged: correct facing ONLY when it actually drifts.
            -- This prevents the turn without a full-rig pivot or movement snap.
            local facingDrift = root.CFrame.LookVector:Dot(lockedLook) < 0.99998
                or root.CFrame.UpVector:Dot(lockedUp) < 0.99998
            if facingDrift then
                root.CFrame = CFrame.new(root.Position) * lockedFacing
            end
            -- Only small upward gaps are grounded; never force a falling player
            -- up onto a different floor or snap the entire character assembly.
            local floorY = floorRootY(current)
            if floorY and current.Y > floorY + 0.65
                and current.Y < floorY + 2.7 and eventActive then
                root.CFrame = CFrame.new(current.X, floorY, current.Z)
                    * lockedFacing
                root.AssemblyLinearVelocity = Vector3.new(sideways.X, 0, sideways.Z)
            end
            if step.Magnitude <= 4 and awayFromSafe < 12 then
                safePosition = CFrame.new(root.Position) * lockedFacing
            end
            previousPosition = root.Position
        end)
        local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        local targetBefore = targetRoot and targetRoot.Position
        local didCarry, didEvent = false, false
        local offset = EVENT_POSITION - CLASSROOM_POSITION
        local function round(n) return math.floor(n + 0.5) end
        -- Same offset argument convention as the working Forcefield.
        local ok, err = pcall(function()
            AntiTPIntentionalTeleportUntil = math.max(
                AntiTPIntentionalTeleportUntil, os.clock() + 0.22)
            carry:FireServer(target, round(offset.X), round(offset.Y),
                round(offset.Z), 0, 0, 0)
            didCarry = true
            task.wait(0.065) -- match Forcefield carry-to-event handoff
            if alive and enabled and revision == generation
                and ownChar == Player.Character and target.Parent == Players
                and not isManualGrabWindow() and not DeathTPIsEscaping
                and hum.Health > 0 then
                ev:FireServer()
                didEvent = true
                eventWindowEnds = os.clock() + 1.1
            end
        end)
        if didCarry and not isManualGrabWindow() then
            task.wait(0.05)
            if not isManualGrabWindow() then
                pcall(function() stop:FireServer() end)
            end
        end
        -- The one-shot Heartbeat guard keeps normal motion natural.
        -- No Counter TP bubble or world-space effect is created.
        if alive and enabled and revision == generation then
            if ok and didEvent then
                attempts += 1
                render("Counter request sent for " .. target.Name ..
                    ". Checking whether the server moved the target...")
            else
                render("Counter interrupted: " ..
                    (not ok and tostring(err) or "game canceled the action."))
            end
        end
        finish()
        if ok and didEvent and targetBefore then
            task.delay(0.8, function()
                if not alive or not enabled or revision ~= generation then return end
                local r = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
                if not r then return end
                local moved = (r.Position - targetBefore).Magnitude
                local toClass = (r.Position - CLASSROOM_POSITION).Magnitude
                if toClass < 20 then
                    render(target.Name .. " appears at the classroom after the hit.")
                elseif moved > 25 then
                    render(("Server moved %s %.0f studs, not near the classroom.")
                        :format(target.Name, moved))
                else
                    render("Hit detected, but server did NOT move " .. target.Name ..
                        ". The game may not allow targeting attackers.")
                end
            end)
        end
    end

    local function detach()
        table.clear(hitQueue)
        queueWorkerRunning = false
        Gui:SetAttribute("CounterTPHitPending", false)
        stopOwnGuard()
        if damageConn then damageConn:Disconnect() damageConn = nil end
        if stateConn then stateConn:Disconnect() stateConn = nil end
        if standConn then standConn:Disconnect() standConn = nil end
        if sampleConn then sampleConn:Disconnect() sampleConn = nil end
        table.clear(nearTimes)
    end
    local function attach(character, revision)
        detach()
        if not character or not enabled or not alive then return end
        local hum = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 8)
        if not hum or not enabled or not alive or revision ~= generation
            or Player.Character ~= character then return end

        -- Record the nearest nine-stud contacts briefly to handle delayed damage.
        local elapsed = 0
        local function sample()
            local root = character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local now = os.clock()
            for _, other in ipairs(Players:GetPlayers()) do
                if nearby(other, root) then nearTimes[other.UserId] = now end
            end
            for uid, at in pairs(nearTimes) do
                if now - at > 0.9 then nearTimes[uid] = nil end
            end
        end
        sample()
        sampleConn = RunService.Heartbeat:Connect(function(dt)
            if not enabled or revision ~= generation then return end
            elapsed += math.min(tonumber(dt) or 0, 0.1)
            if elapsed >= 0.06 then elapsed = 0 sample() end
        end)

        local function hit(signal, damage)
            if not alive or not enabled or revision ~= generation
                or hum.Health <= 0 then return end
            local now = os.clock()
            local actualDamage = (damage or 0) > 0.01
            if actualDamage then
                hitsDetected += 1
                lastDamageAt = now
            else
                -- Keep ragdoll-only hits as a fallback without counting
                -- every state transition from the same knockdown.
                if now - lastDamageAt <= 0.18
                    or now - lastStateHitAt <= 0.20 then return end
                hitsDetected += 1
                lastStateHitAt = now
            end
            if isManualGrabWindow() or DeathTPIsEscaping then
                render(signal .. " detected; paused for manual G/death recovery.")
                return
            end
            local root = character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            local target, reason = findAttacker(hum, root)
            if not target then
                render(signal .. " detected, but " .. reason .. ". No wrong target selected.")
                return
            end
            -- No target cooldown or global hit cooldown. A real damage event
            -- becomes one request, even if an earlier request is in progress.
            if #hitQueue >= MAX_HIT_QUEUE then
                render("Counter TP queue full; refusing excessive overlapping requests.")
                return
            end
            table.insert(hitQueue, {target = target, at = now, signal = signal})
            Gui:SetAttribute("CounterTPHitPending", true)
            render(("%s from %s queued (%d hit%s).")
                :format(signal, target.Name, #hitQueue,
                    #hitQueue == 1 and "" or "s"))
            if queueWorkerRunning then return end
            queueWorkerRunning = true
            task.spawn(function()
                while alive and enabled and revision == generation
                    and Player.Character == character and #hitQueue > 0 do
                    local item = table.remove(hitQueue, 1)
                    local timeoutAt = os.clock() + 8
                    -- Never overlap another teleport owner's request.
                    while alive and enabled and revision == generation
                        and Player.Character == character
                        and (busy or SharedTeleportOwner ~= nil
                            or remotes() == nil
                            or os.clock() < SharedTeleportCooldownUntil
                            or os.clock() < AntiTPIntentionalTeleportUntil
                            or isManualGrabWindow() or DeathTPIsEscaping) do
                        if os.clock() >= timeoutAt then break end
                        task.wait(0.025)
                    end
                    if alive and enabled and revision == generation
                        and Player.Character == character
                        and item.target.Parent == Players
                        and os.clock() < timeoutAt
                        and not busy and SharedTeleportOwner == nil
                        and os.clock() >= SharedTeleportCooldownUntil
                        and os.clock() >= AntiTPIntentionalTeleportUntil
                        and not isManualGrabWindow() and not DeathTPIsEscaping then
                        busy, SharedTeleportOwner = true, "CounterTP"
                        render(("Hit detected: classroom request for %s.")
                            :format(item.target.Name))
                        local ok, err = pcall(
                            sendCounter, item.target, character, revision)
                        if not ok then
                            warn("[VOID HUB COUNTER TP] Worker: " .. tostring(err))
                            if SharedTeleportOwner == "CounterTP" then
                                SharedTeleportOwner = nil
                            end
                            busy = false
                            if alive and enabled then
                                render("Counter request error: " .. tostring(err))
                            end
                        end
                    elseif alive and enabled and revision == generation then
                        render(remotes() and "Hit queued, but another teleport/recovery blocked the request."
                            or "Hit detected but Carry/Event remotes are not available.")
                    end
                end
                if revision == generation then
                    queueWorkerRunning = false
                    Gui:SetAttribute("CounterTPHitPending", false)
                end
            end)
        end

        local oldHealth = hum.Health
        damageConn = hum.HealthChanged:Connect(function(health)
            local damage = oldHealth - health
            oldHealth = health
            if damage > 0.01 then hit("Damage", damage) end
        end)
        stateConn = hum.StateChanged:Connect(function(_, state)
            if state == Enum.HumanoidStateType.Ragdoll
                or state == Enum.HumanoidStateType.FallingDown
                or state == Enum.HumanoidStateType.Physics then
                hit("Knockdown", 0)
            end
        end)
        standConn = hum:GetPropertyChangedSignal("PlatformStand"):Connect(function()
            if hum.PlatformStand then hit("Immobilized", 0) end
        end)
        render("ON. Watching actual hits. Range " .. radius
            .. " studs; 0.9s contact history; no bubble.")
    end

    persistentToggle(button, function()
        enabled = not enabled
        generation += 1
        detach()
        if enabled then
            if not remotes() then
                render("ON. Waiting for compatible Carry / EventTeleport remotes.")
            else
                render("ON. Wait for a real hit; no bubble is created.")
            end
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
        -- Discard queued actions for a player who left.
        for i = #hitQueue, 1, -1 do
            if hitQueue[i].target == p then table.remove(hitQueue, i) end
        end
    end)
    Gui.Destroying:Connect(function()
        alive, enabled = false, false
        generation += 1
        detach()
        if SharedTeleportOwner == "CounterTP" then SharedTeleportOwner = nil end
    end)
    render()
end

-- ============================================================================
