local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local RS                = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera
local MOBILE      = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local API_URL = "http://scriptserver.alwaysdata.net/request.php"
local PING_INTERVAL = 5
local USERS_REFRESH_INTERVAL = 15
local MM2_PLACE_ID = 66654135
local HIGHLIGHT_LIFETIME = 3
local HIGHLIGHT_PRIORITY = 100

local flags = {
    autoKill=false, silentAim=false,
    autoGun=false, knifeWalls=false, instantKnife=false, autoCoins=false,
    coinSpeed=16,
    espInnocent=true, espSheriff=true, espMurderer=true,
    walkSpeed=false, walkSpeedValue=16,
    noclip=false, infJump=false, fly=false, flySpeed=60,
}
local prevNoclip = false
local flingTarget = nil
local flinging = false

local FLING_POWER = 10000
local FLING_MAX_DY = 140
local FLING_MAX_RISE = 320

local T = {
    bg=Color3.fromRGB(18,16,24), panel=Color3.fromRGB(28,24,38),
    panelHi=Color3.fromRGB(42,34,58), inset=Color3.fromRGB(34,28,48),
    text=Color3.fromRGB(240,238,250), sub=Color3.fromRGB(170,164,196),
    dim=Color3.fromRGB(120,112,150), accent=Color3.fromRGB(160,90,255),
    off=Color3.fromRGB(60,52,80), danger=Color3.fromRGB(255,90,120),
    green=Color3.fromRGB(95,225,125), blue=Color3.fromRGB(90,150,255),
    red=Color3.fromRGB(255,80,80),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local FONT_REG = Enum.Font.Gotham

local function new(c,p,k)
    local o = Instance.new(c)
    for a,b in pairs(p or {}) do o[a]=b end
    for _,x in ipairs(k or {}) do x.Parent=o end
    return o
end
local function corner(p,r) local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,r or 8); c.Parent=p; return c end
local function grad(p,c1,c2,rot) local g=Instance.new("UIGradient");
    g.Color=ColorSequence.new(c1,c2); g.Rotation=rot or 0; g.Parent=p; return g end

local function httpGet(url)
    local methods = {
        function() return HttpService:RequestAsync({Url=url, Method="GET"}) end,
        function() return HttpService:GetAsync(url) end,
        function() local ok,r = pcall(function() return game:HttpGet(url) end); if ok then return {Body=r, Success=true} end end,
        function() if typeof(request)=="function" then local ok,r = pcall(request,{Url=url, Method="GET"}); if ok and r then return {Body=r.Body, Success=r.Success} end end end,
        function() if typeof(syn)=="table" and typeof(syn.request)=="function" then local ok,r = pcall(syn.request,{Url=url, Method="GET"}); if ok and r then return {Body=r.Body, Success=r.Success} end end end,
        function() if typeof(http_request)=="function" then local ok,r = pcall(http_request,{Url=url, Method="GET"}); if ok and r then return {Body=r.Body, Success=r.Success} end end end,
    }
    for _, fn in ipairs(methods) do
        local ok, res = pcall(fn)
        if ok and res then
            if type(res)=="table" and res.Body then return res.Body end
            if type(res)=="string" then return res end
        end
    end
    return nil
end

local CRC
pcall(function() CRC = require(RS:WaitForChild("Modules"):WaitForChild("CurrentRoundClient")) end)
local function roundData(p) return CRC and CRC.PlayerData and CRC.PlayerData[p.Name] end
local function getHRP(ch) return ch and ch:FindFirstChild("HumanoidRootPart") end
local function isGunRole(r) return r=="Sheriff" or r=="Hero" end

local tagOwners={}
local function refreshTags()
    for _,tag in ipairs({"Weapon_Gun","Weapon_Knife"}) do
        tagOwners[tag]={}
        for _,t in ipairs(CollectionService:GetTagged(tag)) do
            if t.Parent then tagOwners[tag][t.Parent]=true end
        end
    end
end
refreshTags()
task.spawn(function() while true do refreshTags(); task.wait(0.6) end end)

local function charHasWeapon(ch,kind)
    for _,t in ipairs(ch:GetChildren()) do
        if t:IsA("Tool") then
            if kind=="Gun" and (t.Name=="Gun" or t:FindFirstChild("Shoot")) then return true end
            if kind=="Knife" and (t.Name=="Knife" or t:FindFirstChild("Events")) then return true end
        end
    end
end
local function playerHasTag(p,tag)
    local m=tagOwners[tag]; if not m then return false end
    local ch=p.Character; if ch and m[ch] then return true end
    local bp=p:FindFirstChildOfClass("Backpack"); if bp and m[bp] then return true end
    return false
end
local function roleOf(p)
    local d=roundData(p); local r=d and d.Role
    if r=="Murderer" then return "Murderer" end
    if r=="Sheriff" or r=="Hero" then return r end
    local ch=p.Character
    if playerHasTag(p,"Weapon_Gun") or (ch and charHasWeapon(ch,"Gun")) then return "Hero" end
    if playerHasTag(p,"Weapon_Knife") or (ch and charHasWeapon(ch,"Knife")) then return "Murderer" end
    return r or "Innocent"
end
local function alive(p)
    local d=roundData(p); if d and d.Dead==true then return false end
    local ch=p.Character; local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    return ch and hum and hum.Health>0 and getHRP(ch)
end
local function myRole() return roleOf(LocalPlayer) end
local function findMurderer()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and roleOf(p)=="Murderer" and alive(p) then return p end
    end
end
local function findSheriff()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and isGunRole(roleOf(p)) and alive(p) then return p end
    end
end
local function findWeapon(n)
    local ch=LocalPlayer.Character; local bp=LocalPlayer:FindFirstChildOfClass("Backpack")
    return (ch and ch:FindFirstChild(n)) or (bp and bp:FindFirstChild(n))
end
local function equip(tool)
    local ch=LocalPlayer.Character; local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if tool and hum and tool.Parent~=ch then pcall(function() hum:EquipTool(tool) end) end
end
local function canAct()
    local ch=LocalPlayer.Character; if not ch or not ch.Parent then return false end
    local hum=ch:FindFirstChildOfClass("Humanoid")
    if not (hum and hum.Health>0) then return false end
    return getHRP(ch)~=nil
end

local function roleEspEnabled(role)
    if role=="Murderer" then return flags.espMurderer end
    if isGunRole(role) then return flags.espSheriff end
    return flags.espInnocent
end

local function doTP(pos)
    local ch = LocalPlayer.Character
    if not ch or not ch.Parent then return false end
    local hrp = ch:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    if typeof(pos) ~= "Vector3" then return false end
    if pos.X ~= pos.X or pos.Y ~= pos.Y or pos.Z ~= pos.Z then return false end
    if math.abs(pos.X) > 10000 or math.abs(pos.Z) > 10000 or math.abs(pos.Y) > 10000 then return false end
    local cf = CFrame.new(pos + Vector3.new(0, 3, 0))
    for i = 1, 4 do
        hrp.CFrame = cf
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
        RunService.Heartbeat:Wait()
    end
    return true
end

local KNIFE_PARTS={"HumanoidRootPart","UpperTorso","LowerTorso","Torso","Head"}
local function knifeKill(ev,targetChar)
    if not (ev and targetChar) then return end
    local ht=ev:FindFirstChild("HandleTouched"); local ks=ev:FindFirstChild("KnifeStabbed")
    if not ht then return end
    if ks then ks:FireServer() end
    for _,pn in ipairs(KNIFE_PARTS) do
        local part=targetChar:FindFirstChild(pn)
        if part then ht:FireServer(part); return end
    end
end
local SNAP_HEIGHT=5
local GUN_COOLDOWN=3.25
local snapAt=-10
local snapping=false
local function gunBusy() return os.clock()-snapAt<GUN_COOLDOWN end
local function gunOrigin()
    local ch=LocalPlayer.Character; local hrp=ch and getHRP(ch); if not hrp then return end
    local att=hrp:FindFirstChild("GunRaycastAttachment")
    return att and att.WorldCFrame or hrp.CFrame
end
local function aimPoint(ch)
    local p=ch:FindFirstChild("HumanoidRootPart") or ch:FindFirstChild("UpperTorso")
        or ch:FindFirstChild("Torso") or ch:FindFirstChild("Head")
    return p and p.Position
end
local function snapShot(target)
    if snapping or gunBusy() then return false end
    local gun=findWeapon("Gun"); if not gun then return false end
    local shoot=gun:FindFirstChild("Shoot"); if not shoot then return false end
    local myHrp=getHRP(LocalPlayer.Character)
    local tChar=target and target.Character
    local tHrp=tChar and getHRP(tChar)
    if not (myHrp and tHrp and canAct()) then return false end
    snapping=true
    local home=myHrp.CFrame
    local homeVel=myHrp.AssemblyLinearVelocity
    local fired=false
    pcall(function()
        equip(gun)
        local dl=os.clock()+0.4
        while os.clock()<dl do
            local h=getHRP(LocalPlayer.Character)
            if h and h:FindFirstChild("GunRaycastAttachment") then break end
            RunService.Heartbeat:Wait()
        end
        local aim=aimPoint(tChar); if not aim then return end
        local side=home.Position-aim
        side=Vector3.new(side.X,0,side.Z)
        if side.Magnitude<0.5 then
            local lv=tHrp.CFrame.LookVector; side=Vector3.new(lv.X,0,lv.Z)
        end
        if side.Magnitude<0.5 then side=Vector3.new(0,0,1) end
        side=side.Unit
        local rp=RaycastParams.new()
        rp.FilterType=Enum.RaycastFilterType.Exclude
        rp.FilterDescendantsInstances={tChar,LocalPlayer.Character}
        if Workspace:Raycast(aim,side*SNAP_HEIGHT,rp) then side=-side end
        local relOff=side*SNAP_HEIGHT
        local chest=aim
        local t0=os.clock()
        repeat
            local h=getHRP(LocalPlayer.Character)
            local tr=target.Character and getHRP(target.Character)
            if not (h and tr) then return end
            chest=aimPoint(target.Character) or chest
            h.CFrame=CFrame.new(chest+relOff,chest)
            h.AssemblyLinearVelocity=Vector3.zero
            h.AssemblyAngularVelocity=Vector3.zero
            RunService.Heartbeat:Wait()
        until os.clock()-t0>=0.15
        local origin=gunOrigin()
        if origin then
            local tr2=target.Character and getHRP(target.Character)
            local vel=tr2 and tr2.AssemblyLinearVelocity or Vector3.zero
            shoot:FireServer(origin,CFrame.new(chest+vel*0.08))
            snapAt=os.clock()
            fired=true
            local t1=os.clock()
            repeat
                local h=getHRP(LocalPlayer.Character)
                if h then h.CFrame=CFrame.new(chest+relOff,chest); h.AssemblyLinearVelocity=Vector3.zero end
                RunService.Heartbeat:Wait()
            until os.clock()-t1>=0.25
        end
    end)
    local h3=getHRP(LocalPlayer.Character)
    if h3 then h3.CFrame=home; h3.AssemblyLinearVelocity=homeVel; h3.AssemblyAngularVelocity=Vector3.zero end
    snapping=false
    return fired
end

task.spawn(function()
    while true do
        if flags.autoKill and canAct() then
            local role=myRole()
            if role=="Murderer" then
                local knife=findWeapon("Knife"); local ev=knife and knife:FindFirstChild("Events")
                if ev then
                    equip(knife)
                    for _,tgt in ipairs(Players:GetPlayers()) do
                        if tgt~=LocalPlayer and alive(tgt) then knifeKill(ev,tgt.Character) end
                    end
                end
                task.wait(0.08)
            elseif isGunRole(role) then
                local m=findMurderer(); if m then snapShot(m) end
                task.wait(0.08)
            else task.wait(0.12) end
        else task.wait(0.1) end
    end
end)

local SCREEN
local Crosshair
local function aimCenter()
    local m=UserInputService:GetMouseLocation()
    return Vector2.new(m.X,m.Y)
end
local function lockTarget()
    local mr = myRole()
    if mr == "Murderer" then
        local best,bd
        local center = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
        for _,p in ipairs(Players:GetPlayers()) do
            if p~=LocalPlayer and alive(p) and roleOf(p)~="Murderer" then
                local hrp=getHRP(p.Character)
                if hrp then
                    local v,on=Camera:WorldToViewportPoint(hrp.Position)
                    if on and v.Z>0 then
                        local d=(Vector2.new(v.X,v.Y)-center).Magnitude
                        if not bd or d<bd then bd,best=d,p end
                    end
                end
            end
        end
        return best
    else
        return findMurderer()
    end
end

local function buildCrosshair()
    if Crosshair and Crosshair.Parent then return end
    Crosshair = Instance.new("Frame")
    Crosshair.Name = "Crosshair"
    Crosshair.AnchorPoint = Vector2.new(0.5,0.5)
    Crosshair.Position = UDim2.fromScale(0.5,0.5)
    Crosshair.Size = UDim2.fromOffset(18,18)
    Crosshair.BackgroundTransparency = 1
    Crosshair.BorderSizePixel = 0
    Crosshair.Visible = false
    Crosshair.ZIndex = 50
    Crosshair.Parent = SCREEN

    local hBar = Instance.new("Frame")
    hBar.AnchorPoint = Vector2.new(0.5,0.5)
    hBar.Position = UDim2.fromScale(0.5,0.5)
    hBar.Size = UDim2.fromOffset(18,2)
    hBar.BackgroundColor3 = Color3.fromRGB(255,255,255)
    hBar.BorderSizePixel = 0
    hBar.ZIndex = 51
    hBar.Parent = Crosshair
    corner(hBar,1)

    local vBar = Instance.new("Frame")
    vBar.AnchorPoint = Vector2.new(0.5,0.5)
    vBar.Position = UDim2.fromScale(0.5,0.5)
    vBar.Size = UDim2.fromOffset(2,18)
    vBar.BackgroundColor3 = Color3.fromRGB(255,255,255)
    vBar.BorderSizePixel = 0
    vBar.ZIndex = 51
    vBar.Parent = Crosshair
    corner(vBar,1)

    local dot = Instance.new("Frame")
    dot.AnchorPoint = Vector2.new(0.5,0.5)
    dot.Position = UDim2.fromScale(0.5,0.5)
    dot.Size = UDim2.fromOffset(3,3)
    dot.BackgroundColor3 = Color3.fromRGB(255,60,60)
    dot.BorderSizePixel = 0
    dot.ZIndex = 52
    dot.Parent = Crosshair
    corner(dot,2)

    local s1 = Instance.new("UIStroke"); s1.Color=Color3.fromRGB(0,0,0); s1.Thickness=1; s1.Transparency=0.5; s1.Parent=hBar
    local s2 = Instance.new("UIStroke"); s2.Color=Color3.fromRGB(0,0,0); s2.Thickness=1; s2.Transparency=0.5; s2.Parent=vBar
end

local lastFirstPerson = false
local function setFirstPerson(on)
    if on == lastFirstPerson then return end
    lastFirstPerson = on
    pcall(function()
        if on then
            LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
        else
            LocalPlayer.CameraMode = Enum.CameraMode.Classic
        end
    end)
end

RunService.RenderStepped:Connect(function()
    if not SCREEN then return end
    if flags.silentAim then
        if not Crosshair then buildCrosshair() end
        Crosshair.Visible = true
    elseif Crosshair then
        Crosshair.Visible = false
    end
    setFirstPerson(flags.silentAim)
    if flags.silentAim then
        local t = lockTarget()
        if t then
            local th=t.Character:FindFirstChild("Head") or getHRP(t.Character)
            if th then
                Camera.CFrame=Camera.CFrame:Lerp(CFrame.new(Camera.CFrame.Position,th.Position),0.5)
            end
        end
    end
end)

local droppedGun
local grabbing=false
local function findDroppedGun()
    for _,p in ipairs(CollectionService:GetTagged("GunDrop")) do
        if p:IsA("BasePart") and p:IsDescendantOf(Workspace) then return p end
    end
    for _,d in ipairs(Workspace:GetDescendants()) do
        if d:IsA("BasePart") and d.Name=="GunDrop" then return d end
    end
end
local function touchGun(h)
    local hrp=getHRP(LocalPlayer.Character)
    if not (hrp and h and h.Parent) then return false end
    if typeof(firetouchinterest)=="function" then
        pcall(function() for _=1,4 do firetouchinterest(hrp,h,0); firetouchinterest(hrp,h,1) end end)
    end
    return findWeapon("Gun")~=nil
end
local function grabGunOnce(target)
    if grabbing then return false end
    local h=target or droppedGun or findDroppedGun()
    local hrp=getHRP(LocalPlayer.Character)
    if not (h and h.Parent and hrp and canAct()) then return false end
    grabbing=true
    if touchGun(h) then grabbing=false; return true end
    local back=hrp.CFrame
    for _=1,10 do
        local myhrp=getHRP(LocalPlayer.Character)
        if not (myhrp and h.Parent) then break end
        myhrp.CFrame=CFrame.new(h.Position)
        myhrp.AssemblyLinearVelocity=Vector3.zero
        if touchGun(h) then break end
        RunService.Heartbeat:Wait()
    end
    local myhrp=getHRP(LocalPlayer.Character)
    if myhrp then myhrp.CFrame=back; myhrp.AssemblyLinearVelocity=Vector3.zero end
    local got=findWeapon("Gun")~=nil
    grabbing=false
    return got
end
task.spawn(function()
    while true do
        if flags.autoGun then
            local g=findDroppedGun(); droppedGun=g
            if g and not grabbing and myRole()~="Murderer" and not findWeapon("Gun") and canAct() then
                grabGunOnce(g)
            end
        end
        task.wait(0.15)
    end
end)

local function aimRay() local c=aimCenter() return Camera:ViewportPointToRay(c.X,c.Y) end
local function closestPlayerPos(radius)
    local center = aimCenter()
    local best, bd
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and alive(p) then
            local hrp = getHRP(p.Character)
            if hrp then
                local v, on = Camera:WorldToViewportPoint(hrp.Position)
                if on and v.Z > 0 then
                    local d = (Vector2.new(v.X, v.Y) - center).Magnitude
                    if d <= radius and (not bd or d < bd) then bd, best = d, p end
                end
            end
        end
    end
    return best
end
local function wallAimPos()
    local ray = aimRay()
    local origin, dir = ray.Origin, ray.Direction.Unit
    local far = origin + dir * 300
    local chars = {}
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LocalPlayer and alive(p) and p.Character then chars[#chars+1] = p.Character end
    end
    if #chars == 0 then return nil, far end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = chars
    local hit = Workspace:Raycast(origin, dir*300, params)
    if hit then return hit.Position, far end
    local p = closestPlayerPos(60)
    if p then
        local hrp = getHRP(p.Character)
        if hrp then return hrp.Position, far end
    end
    return nil, far
end

local instantFiredAt = -10
local function throwKnifeNow()
    local ch = LocalPlayer.Character
    if not ch then return end
    local knife = ch:FindFirstChild("Knife")
    if not knife then
        local bp = LocalPlayer:FindFirstChild("Backpack")
        local st = bp and bp:FindFirstChild("Knife")
        if st then
            local hum = ch:FindFirstChildOfClass("Humanoid")
            if hum then pcall(function() hum:EquipTool(st) end) end
            knife = ch:FindFirstChild("Knife") or st
        end
    end
    if not knife then return end
    local ev = knife:FindFirstChild("Events")
    local thrown = ev and ev:FindFirstChild("KnifeThrown")
    if not thrown then return end
    if knife:GetAttribute("Disabled") == true then return end
    local cd = 2*(tonumber(knife:GetAttribute("ThrowSpeed")) or 1)
    if os.clock()-instantFiredAt < cd then return end
    local target
    if flags.knifeWalls then
        local snap, far = wallAimPos()
        target = snap or far
    else
        local p = closestPlayerPos(60)
        if p then
            local hrp = getHRP(p.Character)
            if hrp then target = hrp.Position end
        end
        if not target then
            local ray = aimRay()
            target = ray.Origin + ray.Direction.Unit * 300
        end
    end
    if not target then return end
    local hrp = getHRP(ch)
    if not hrp then return end
    local d = target - hrp.Position
    d = (d.Magnitude > 0.1) and d.Unit or Vector3.new(0,0,-1)
    instantFiredAt = os.clock()
    local handle = knife:FindFirstChild("Handle")
    local origin
    if flags.knifeWalls then
        origin = CFrame.new(target - d*0.6, target)
    elseif handle then
        origin = handle.CFrame
    else
        origin = CFrame.new(target - d*0.6, target)
    end
    pcall(function() thrown:FireServer(origin, CFrame.new(target)) end)
end

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
    if flags.instantKnife then throwKnifeNow() end
end)

task.spawn(function()
    local ok, act = pcall(function()
        local ic = LocalPlayer:WaitForChild("PlayerGui", 10):WaitForChild("InputContext", 10)
        return ic:WaitForChild("GameplayContext", 10):WaitForChild("Throw", 10)
    end)
    if ok and act then
        pcall(function()
            act.Pressed:Connect(function()
                if flags.instantKnife then throwKnifeNow() end
            end)
        end)
    end
end)

pcall(function()
    if typeof(hookmetamethod) ~= "function"
        or typeof(newcclosure) ~= "function"
        or typeof(checkcaller) ~= "function"
        or typeof(getnamecallmethod) ~= "function" then
        error("no hook support")
    end
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecallmethod()
        if method == "FireServer" and self.Name == "KnifeThrown" and flags.knifeWalls then
            local args = {...}
            if args[2] and typeof(args[2]) == "CFrame" then
                local snap = select(1, wallAimPos())
                if snap then
                    args[2] = CFrame.new(snap)
                    if args[1] and typeof(args[1]) == "CFrame" then
                        local d = snap - args[1].Position
                        d = (d.Magnitude > 0.1) and d.Unit or Vector3.new(0,0,-1)
                        args[1] = CFrame.new(snap - d*0.6, snap)
                    end
                end
            end
            return oldNamecall(self, table.unpack(args))
        end
        return oldNamecall(self, ...)
    end))
end)

local coinCache={}
local coinContainerRef
local function getCoinContainer()
    if coinContainerRef and coinContainerRef.Parent then return coinContainerRef end
    local map=CollectionService:GetTagged("CurrentMap")[1]
    coinContainerRef=(map and map:FindFirstChild("CoinContainer")) or Workspace:FindFirstChild("CoinContainer",true)
    return coinContainerRef
end
local function coinTaken(d) local c=d:GetAttribute("Collected"); return c==true or c=="true" end
local function freshCoins()
    local out={}
    local tagged=CollectionService:GetTagged("ServerCoinPart")
    if #tagged>0 then
        for _,d in ipairs(tagged) do
            if d:IsA("BasePart") and d.Parent and not coinTaken(d) then out[#out+1]=d end
        end
        return out
    end
    local c=getCoinContainer()
    if c then
        for _,d in ipairs(c:GetChildren()) do
            if d:IsA("BasePart") and (d:GetAttribute("CoinID")~=nil or d.Name=="Coin_Server") and not coinTaken(d) then out[#out+1]=d end
        end
    end
    return out
end
task.spawn(function()
    while true do
        if flags.autoCoins then coinCache=freshCoins(); task.wait(0.2)
        else if #coinCache>0 then coinCache={} end; task.wait(0.8) end
    end
end)
task.spawn(function()
    local target,since,farming,prevWS
    local function standDown()
        if not farming then return end
        farming=false
        local ch=LocalPlayer.Character
        local hum=ch and ch:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum.PlatformStand=false; if prevWS then hum.WalkSpeed=prevWS end end) end
        prevWS=nil
    end
    while true do
        if flags.autoCoins and alive(LocalPlayer) then
            local ch=LocalPlayer.Character
            local hrp=getHRP(ch); local hum=ch and ch:FindFirstChildOfClass("Humanoid")
            if hrp and hum then
                local coin,bd
                for _,c in ipairs(coinCache) do
                    if c.Parent and not coinTaken(c) then
                        local d=(c.Position-hrp.Position).Magnitude
                        if d<=250 and (not bd or d<bd) then bd,coin=d,c end
                    end
                end
                if coin then
                    if not farming then farming=true; prevWS=hum.WalkSpeed; pcall(function() hum.PlatformStand=true end) end
                    local spd = math.clamp(flags.coinSpeed,1,200)
                    pcall(function() hum.WalkSpeed=spd end)
                    if coin~=target then target=coin; since=os.clock() end
                    if os.clock()-since>5 then target=nil; task.wait()
                    else
                        local dt=RunService.RenderStepped:Wait()
                        local dir=coin.Position-hrp.Position
                        if dir.Magnitude>2 then
                            hrp.CFrame=CFrame.new(hrp.Position+dir.Unit*math.min(dir.Magnitude,spd*dt))
                            hrp.AssemblyLinearVelocity=Vector3.zero
                        end
                        if typeof(firetouchinterest)=="function" then
                            pcall(function() firetouchinterest(hrp,coin,0); firetouchinterest(hrp,coin,1) end)
                        end
                    end
                else standDown(); target=nil; task.wait(0.25) end
            else task.wait(0.1) end
        else standDown(); target=nil; task.wait(0.2) end
    end
end)

local function applyWalkSpeed()
    local ch=LocalPlayer.Character
    if not ch then return end
    local hum=ch:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed=flags.walkSpeedValue end
end

local flyBV,flyBG
local function startFly()
    local ch=LocalPlayer.Character; local hrp=getHRP(ch); local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end
    hum.PlatformStand=true
    flyBV=Instance.new("BodyVelocity"); flyBV.MaxForce=Vector3.new(1,1,1)*9e9; flyBV.P=9e4; flyBV.Velocity=Vector3.zero; flyBV.Parent=hrp
    flyBG=Instance.new("BodyGyro"); flyBG.MaxTorque=Vector3.new(1,1,1)*9e9; flyBG.P=9e4; flyBG.CFrame=hrp.CFrame; flyBG.Parent=hrp
end
local function stopFly()
    local ch=LocalPlayer.Character; local hum=ch and ch:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand=false end
    if flyBV then flyBV:Destroy(); flyBV=nil end
    if flyBG then flyBG:Destroy(); flyBG=nil end
end
local _controls
local function moveVector()
    if not _controls then
        pcall(function() _controls=require(LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls() end)
    end
    if _controls then
        local ok,mv=pcall(function() return _controls:GetMoveVector() end)
        if ok then return mv end
    end
end
RunService.RenderStepped:Connect(function()
    if not flags.fly or not flyBV then return end
    local hrp=getHRP(LocalPlayer.Character); if not hrp then return end
    local dir=Vector3.zero
    local look,right=Camera.CFrame.LookVector,Camera.CFrame.RightVector
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir+=look end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir-=look end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir+=right end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir-=right end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir+=Vector3.new(0,1,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir-=Vector3.new(0,1,0) end
    if dir.Magnitude==0 then
        local mv=moveVector()
        if mv and mv.Magnitude>0 then dir=dir+(look*(-mv.Z))+(right*mv.X) end
    end
    flyBV.Velocity=(dir.Magnitude>0 and dir.Unit or Vector3.zero)*flags.flySpeed
    flyBG.CFrame=Camera.CFrame
end)

local noclipConn
local function setNoclip(on)
    flags.noclip=on
    if noclipConn then noclipConn:Disconnect(); noclipConn=nil end
    if on then
        noclipConn=RunService.Stepped:Connect(function()
            local ch=LocalPlayer.Character
            if ch then
                for _,p in ipairs(ch:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then p.CanCollide=false end
                end
            end
        end)
    end
end
UserInputService.JumpRequest:Connect(function()
    if flags.infJump then
        local hum=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

local function startFling(p)
    if flinging or not p or not p.Character then return end
    local myChar = LocalPlayer.Character
    local myHrp = myChar and getHRP(myChar)
    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
    if not (myHrp and myHum) then return end
    local tHrp = getHRP(p.Character)
    if not tHrp then return end

    flingTarget = p
    flinging = true

    local backPos = myHrp.Position
    myHum.PlatformStand = true
    setNoclip(true)

    task.spawn(function()
        local movel = 0.1
        local claimed

        while flinging and flingTarget == p do
            local ch = LocalPlayer.Character
            local tChar = p.Character
            if not ch or not tChar then break end
            local h = ch:FindFirstChild("HumanoidRootPart")
            local t = tChar:FindFirstChild("HumanoidRootPart")
            local tHum = tChar:FindFirstChildOfClass("Humanoid")
            if not (h and t and tHum and tHum.Health > 0) then break end

            local tp = t.Position
            if math.abs(tp.Y - backPos.Y) > FLING_MAX_DY then
                backPos = h.Position
            end

            h.CFrame = t.CFrame

            if typeof(sethiddenproperty) == "function" then
                pcall(function() sethiddenproperty(h, "PhysicsRepRootPart", t) end)
                claimed = h
            end

            local vel = h.AssemblyLinearVelocity
            h.AssemblyLinearVelocity = vel * FLING_POWER + Vector3.new(0, FLING_POWER, 0)
            RunService.RenderStepped:Wait()
            if not h.Parent then break end

            h.AssemblyLinearVelocity = vel
            RunService.Stepped:Wait()
            if not h.Parent then break end

            h.AssemblyLinearVelocity = vel + Vector3.new(0, movel, 0)
            movel = -movel

            RunService.Heartbeat:Wait()
        end

        if claimed and typeof(sethiddenproperty) == "function" then
            pcall(function() sethiddenproperty(claimed, "PhysicsRepRootPart", nil) end)
        end

        local hh = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if hh then
            hh.CFrame = CFrame.new(backPos + Vector3.new(0, 4, 0))
            hh.AssemblyLinearVelocity = Vector3.zero
            hh.AssemblyAngularVelocity = Vector3.zero
        end
        local mh = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if mh then mh.PlatformStand = false end
        setNoclip(false)

        flinging = false
        flingTarget = nil
    end)
end

local function stopFling()
    flinging = false
    flingTarget = nil
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "J3rryHub"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999
do
    local ok = pcall(function()
        if typeof(gethui) == "function" then
            local h = gethui()
            if h then screenGui.Parent = h end
        end
    end)
    if not screenGui.Parent then
        pcall(function() screenGui.Parent = game:GetService("CoreGui") end)
    end
    if not screenGui.Parent then
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end
end
SCREEN = screenGui

local ESP_FOLDER = Instance.new("Folder")
ESP_FOLDER.Name = "_J3rryESP_" .. tostring(math.random(100000,999999))
ESP_FOLDER.Parent = Workspace

local hubUsers = {}
local hubOwners = {}
local hubUserLookup = {}

local function refreshHubUsers()
    task.spawn(function()
        local body = httpGet(API_URL .. "?action=users")
        if not body then return end
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not ok or type(data) ~= "table" then return end
        local newOwners = {}
        local newUsers = {}
        local newLookup = {}
        if type(data.owners) == "table" then
            for _, name in ipairs(data.owners) do
                newOwners[name] = true
                newLookup[name:lower()] = "owner"
            end
        end
        if type(data.users) == "table" then
            for _, name in ipairs(data.users) do
                newUsers[name] = true
                if not newLookup[name:lower()] then
                    newLookup[name:lower()] = "user"
                end
            end
        end
        hubOwners = newOwners
        hubUsers = newUsers
        hubUserLookup = newLookup
    end)
end

task.spawn(function()
    while true do
        local url = API_URL .. "?action=ping"
            .. "&username=" .. HttpService:UrlEncode(LocalPlayer.Name)
            .. "&userId=" .. tostring(LocalPlayer.UserId)
            .. "&jobId=" .. HttpService:UrlEncode(game.JobId)
            .. "&placeId=" .. tostring(game.PlaceId)
            .. "&players=" .. tostring(#Players:GetPlayers())
            .. "&maxPlayers=" .. tostring(Players.MaxPlayers)
        pcall(function() httpGet(url) end)
        task.wait(PING_INTERVAL)
    end
end)

task.spawn(function()
    task.wait(5)
    refreshHubUsers()
    while true do
        task.wait(USERS_REFRESH_INTERVAL)
        refreshHubUsers()
    end
end)

local function getHubTag(plr)
    local kind = hubUserLookup[plr.Name:lower()]
    if kind == "owner" then return "owner"
    elseif kind == "user" then return "user"
    end
    return nil
end

local espStore = {}
local function roleColor(role)
    if role=="Murderer" then return T.red end
    if isGunRole(role) then return T.blue end
    return T.green
end
local function roleName(role)
    if role=="Murderer" then return "MURDERER" end
    if role=="Sheriff" then return "SHERIFF" end
    if role=="Hero" then return "HERO" end
    return "INNOCENT"
end

local function ensureFolderAlive()
    if not ESP_FOLDER or not ESP_FOLDER.Parent then
        ESP_FOLDER = Instance.new("Folder")
        ESP_FOLDER.Name = "_J3rryESP_" .. tostring(math.random(100000,999999))
        ESP_FOLDER.Parent = Workspace
    end
end

local function buildHighlight(ch)
    local hl = Instance.new("Highlight")
    hl.Name = "JH_HL_" .. tostring(math.random(100000,999999))
    hl.FillTransparency = 0.35
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = ch
    pcall(function() hl.Priority = HIGHLIGHT_PRIORITY end)
    hl.Parent = ESP_FOLDER
    return hl
end

local function buildBillboard(p)
    local bb = Instance.new("BillboardGui")
    bb.Name = "JH_BB_" .. tostring(p.UserId)
    bb.Size = UDim2.fromOffset(420, 62)
    bb.AlwaysOnTop = true
    bb.Enabled = false
    bb.MaxDistance = 0
    bb.LightInfluence = 0
    bb.StudsOffsetWorldSpace = Vector3.new(0, 4.3, 0)
    bb.Parent = ESP_FOLDER

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.new(0,0,0,0)
    lbl.Size = UDim2.new(1,0,0.5,0)
    lbl.Font = FONT_BOLD
    lbl.TextSize = 16
    lbl.TextColor3 = T.text
    lbl.TextStrokeTransparency = 0.3
    lbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    lbl.Text = ""
    lbl.TextYAlignment = Enum.TextYAlignment.Bottom
    lbl.Parent = bb

    local tag = Instance.new("TextLabel")
    tag.BackgroundTransparency = 1
    tag.Position = UDim2.new(0,0,0.5,0)
    tag.Size = UDim2.new(1,0,0.5,0)
    tag.Font = FONT_BOLD
    tag.TextSize = 22
    tag.TextColor3 = Color3.fromRGB(0,0,0)
    tag.TextStrokeTransparency = 0
    tag.TextStrokeColor3 = Color3.fromRGB(255,255,255)
    tag.Text = ""
    tag.TextYAlignment = Enum.TextYAlignment.Top
    tag.Parent = bb

    return bb, lbl, tag
end

local function createEsp(p)
    local e = {}
    e.hl = nil
    e.hlFor = nil
    e.hlCreatedAt = 0
    local bb, lbl, tag = buildBillboard(p)
    e.bb = bb
    e.lbl = lbl
    e.tag = tag
    return e
end

local function isHighlightValid(e, ch)
    if not e.hl then return false end
    if not e.hl.Parent then return false end
    if e.hl.Parent ~= ESP_FOLDER then return false end
    if e.hl.Adornee ~= ch then return false end
    if e.hlFor ~= ch then return false end
    if os.clock() - e.hlCreatedAt > HIGHLIGHT_LIFETIME then return false end
    return true
end

local function ensureEsp(p, ch)
    ensureFolderAlive()
    local e = espStore[p]
    if not e then
        e = createEsp(p)
        espStore[p] = e
    end

    if not e.bb or not e.bb.Parent or e.bb.Parent ~= ESP_FOLDER then
        if e.bb then pcall(function() e.bb:Destroy() end) end
        local bb, lbl, tag = buildBillboard(p)
        e.bb = bb
        e.lbl = lbl
        e.tag = tag
    end

    if not isHighlightValid(e, ch) then
        if e.hl then pcall(function() e.hl:Destroy() end) end
        e.hl = buildHighlight(ch)
        e.hlFor = ch
        e.hlCreatedAt = os.clock()
    end

    return e
end
local function clearEsp(p)
    local e = espStore[p]; if not e then return end
    if e.hl then pcall(function() e.hl:Destroy() end) end
    if e.bb then pcall(function() e.bb:Destroy() end) end
    espStore[p] = nil
end

local hue = 0
RunService.RenderStepped:Connect(function(dt)
    if not SCREEN then return end
    ensureFolderAlive()
    hue = (hue + dt * 0.5) % 1
    local ownerColor = Color3.fromHSV(hue, 0.9, 1)
    local camP = Camera.CFrame.Position
    for _, p in ipairs(Players:GetPlayers()) do
        local ch = p.Character
        local hrp = ch and getHRP(ch)
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local show = ch and hrp and hum and hum.Health > 0
        local role = show and roleOf(p) or nil

        local isSelf = (p == LocalPlayer)
        local tagKind = getHubTag(p)

        if show and (isSelf or roleEspEnabled(role)) then
            local col = roleColor(role)
            local dist = math.floor((hrp.Position - camP).Magnitude)
            local e = ensureEsp(p, ch)

            local hlFill, hlOutline
            if tagKind == "owner" then
                hlFill = ownerColor
                hlOutline = Color3.fromRGB(255,255,255)
            elseif tagKind == "user" then
                hlFill = Color3.fromRGB(0,0,0)
                hlOutline = Color3.fromRGB(255,255,255)
            else
                hlFill = col
                hlOutline = col
            end

            if e.hl then
                e.hl.FillColor = hlFill
                e.hl.OutlineColor = hlOutline
                e.hl.FillTransparency = 0.35
                e.hl.OutlineTransparency = 0
                e.hl.Enabled = true
                if e.hl.Adornee ~= ch then e.hl.Adornee = ch end
                pcall(function() e.hl.Priority = HIGHLIGHT_PRIORITY end)
            end

            e.bb.Enabled = true
            e.bb.Adornee = ch:FindFirstChild("Head") or hrp

            local prefix = isSelf and "[YOU] " or ""
            e.lbl.Text = prefix.."["..roleName(role).."]  "..p.Name.."  ["..dist.."m AWAY]"
            e.lbl.TextColor3 = col
            e.lbl.TextStrokeColor3 = Color3.fromRGB(0,0,0)

            if tagKind == "owner" then
                e.tag.Text = "[J3RRY HUB OWNER] J3rryKidd"
                e.tag.TextColor3 = ownerColor
                e.tag.TextStrokeColor3 = Color3.fromRGB(0,0,0)
                e.tag.Visible = true
            elseif tagKind == "user" then
                e.tag.Text = "Also uses J3rry Hub!"
                e.tag.TextColor3 = Color3.fromRGB(0,0,0)
                e.tag.TextStrokeColor3 = Color3.fromRGB(255,255,255)
                e.tag.Visible = true
            else
                e.tag.Visible = false
                e.tag.Text = ""
            end
        else
            clearEsp(p)
        end
    end
end)
Players.PlayerRemoving:Connect(clearEsp)

local function computeSize()
    local vp = Camera.ViewportSize
    if MOBILE then
        return math.min(vp.X - 24, 340), math.min(vp.Y - 80, 400)
    else
        return math.min(vp.X - 200, 520), math.min(vp.Y - 120, 560)
    end
end
local W, H = computeSize()

local root = Instance.new("Frame")
root.Name = "Root"
root.Size = UDim2.fromOffset(W,H)
root.Position = UDim2.new(0.5,-W/2,0.5,-H/2)
root.BackgroundColor3 = T.bg
root.BorderSizePixel = 0
root.Active = true
root.ClipsDescendants = true
root.Parent = screenGui
corner(root,14)
grad(root,T.bg,Color3.fromRGB(28,22,44),135)

local header = Instance.new("Frame")
header.Size = UDim2.new(1,0,0,44)
header.BackgroundColor3 = T.panel
header.BorderSizePixel = 0
header.Active = true
header.Parent = root
corner(header,14)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(14,0)
title.Size = UDim2.new(1,-90,1,0)
title.Font = FONT_BOLD
title.TextSize = MOBILE and 15 or 17
title.TextColor3 = T.accent
title.Text = "J3rry Hub - MM2"
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header
grad(title,T.accent,Color3.fromRGB(80,190,255),0)

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(28,28)
minBtn.Position = UDim2.new(1,-68,0,8)
minBtn.BackgroundColor3 = T.inset
minBtn.Text = "-"
minBtn.TextColor3 = T.text
minBtn.Font = FONT_BOLD
minBtn.TextSize = 18
minBtn.AutoButtonColor = false
minBtn.BorderSizePixel = 0
minBtn.Parent = header
corner(minBtn,7)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28,28)
closeBtn.Position = UDim2.new(1,-36,0,8)
closeBtn.BackgroundColor3 = T.inset
closeBtn.Text = "X"
closeBtn.TextColor3 = T.text
closeBtn.Font = FONT_BOLD
closeBtn.TextSize = 14
closeBtn.AutoButtonColor = false
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
corner(closeBtn,7)

local function addHover(btn, idleCol, hotCol)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=hotCol}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.15),{BackgroundColor3=idleCol}):Play()
    end)
end
addHover(minBtn,T.inset,T.panelHi)
addHover(closeBtn,T.inset,Color3.fromRGB(120,50,70))

local dragging, dragStart, startPos = false, nil, nil
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = root.Position
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        root.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end)

local tabScroll = Instance.new("ScrollingFrame")
tabScroll.Size = UDim2.new(1,-16,0,32)
tabScroll.Position = UDim2.fromOffset(8,50)
tabScroll.BackgroundTransparency = 1
tabScroll.BorderSizePixel = 0
tabScroll.ScrollBarThickness = 0
tabScroll.CanvasSize = UDim2.new(0,0,0,0)
tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
tabScroll.ScrollingEnabled = true
tabScroll.Active = true
tabScroll.Parent = root

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0,6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center
tabLayout.Parent = tabScroll

local pageArea = Instance.new("Frame")
pageArea.Size = UDim2.new(1,-16,1,-118)
pageArea.Position = UDim2.fromOffset(8,86)
pageArea.BackgroundTransparency = 1
pageArea.ClipsDescendants = true
pageArea.Parent = root

local watermark = Instance.new("TextLabel")
watermark.Name = "Watermark"
watermark.BackgroundTransparency = 1
watermark.AnchorPoint = Vector2.new(0.5,1)
watermark.Position = UDim2.new(0.5,0,1,-6)
watermark.Size = UDim2.new(1,-16,0,22)
watermark.Font = FONT_BOLD
watermark.TextSize = MOBILE and 10 or 12
watermark.TextColor3 = T.text
watermark.TextStrokeTransparency = 0.5
watermark.TextXAlignment = Enum.TextXAlignment.Center
watermark.Text = "J3rry Hub - Made by @J3rryKidd (@nexora.j on tiktok)"
watermark.Parent = root
grad(watermark, T.accent, Color3.fromRGB(80,190,255), 0)

local TAB_DEFS = {
    {name="Sheriff",  key="sheriff"},
    {name="Murder",   key="murder"},
    {name="Farm",     key="farm"},
    {name="Fling",    key="fling"},
    {name="Servers",  key="servers"},
    {name="Teleport", key="teleport"},
    {name="Player",   key="player"},
    {name="ESP",      key="esp"},
}
local PAGES = {}
for _,def in ipairs(TAB_DEFS) do
    local page = Instance.new("Frame")
    page.Size = UDim2.fromScale(1,1)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = pageArea

    local sc = Instance.new("ScrollingFrame")
    sc.Size = UDim2.fromScale(1,1)
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 4
    sc.ScrollBarImageColor3 = T.accent
    sc.ScrollBarImageTransparency = 0.3
    sc.CanvasSize = UDim2.new(0,0,0,0)
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.ScrollingDirection = Enum.ScrollingDirection.Y
    sc.ScrollingEnabled = true
    sc.Active = true
    sc.Parent = page

    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0,6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sc

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0,4)
    pad.PaddingBottom = UDim.new(0,8)
    pad.PaddingLeft = UDim.new(0,4)
    pad.PaddingRight = UDim.new(0,4)
    pad.Parent = sc

    PAGES[def.key] = {frame=page, scroll=sc}
end

local activeTab
local tabBtns = {}
local function selectTab(key)
    if activeTab==key then return end
    if activeTab then
        local old = PAGES[activeTab].frame
        local oldB = tabBtns[activeTab]
        old.Visible = false
        old.Position = UDim2.fromOffset(0,0)
        if oldB then
            TweenService:Create(oldB,TweenInfo.new(0.15),{BackgroundColor3=T.panel,TextColor3=T.sub}):Play()
        end
    end
    activeTab=key
    local newP = PAGES[key].frame
    newP.Visible=true
    newP.Position=UDim2.fromOffset(15,0)
    TweenService:Create(newP,TweenInfo.new(0.22,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),
        {Position=UDim2.fromOffset(0,0)}):Play()
    local newB = tabBtns[key]
    if newB then
        TweenService:Create(newB,TweenInfo.new(0.15),{BackgroundColor3=T.panelHi,TextColor3=T.text}):Play()
    end
end

for i,def in ipairs(TAB_DEFS) do
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(78,26)
    b.BackgroundColor3 = T.panel
    b.Text = def.name
    b.TextColor3 = T.sub
    b.Font = FONT
    b.TextSize = MOBILE and 11 or 12
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.LayoutOrder = i
    b.Parent = tabScroll
    corner(b,8)
    tabBtns[def.key]=b

    b.MouseEnter:Connect(function()
        if activeTab~=def.key then
            TweenService:Create(b,TweenInfo.new(0.15),{BackgroundColor3=T.panelHi,TextColor3=T.text}):Play()
        end
    end)
    b.MouseLeave:Connect(function()
        if activeTab~=def.key then
            TweenService:Create(b,TweenInfo.new(0.15),{BackgroundColor3=T.panel,TextColor3=T.sub}):Play()
        end
    end)
    b.MouseButton1Click:Connect(function() selectTab(def.key) end)
end

local function buildToggle(parent, text, key, order, onToggle)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1,0,0,34)
    row.BackgroundColor3 = T.inset
    row.AutoButtonColor = false
    row.Text = ""
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent
    corner(row,8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(12,0)
    lbl.Size = UDim2.new(1,-64,1,0)
    lbl.Font = FONT
    lbl.TextSize = MOBILE and 12 or 13
    lbl.TextColor3 = T.sub
    lbl.Text = text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local trk = Instance.new("Frame")
    trk.AnchorPoint = Vector2.new(1,0.5)
    trk.Position = UDim2.new(1,-12,0.5,0)
    trk.Size = UDim2.fromOffset(42,22)
    trk.BackgroundColor3 = T.off
    trk.BorderSizePixel = 0
    trk.Parent = row
    corner(trk,11)

    local knb = Instance.new("Frame")
    knb.AnchorPoint = Vector2.new(0,0.5)
    knb.Position = UDim2.new(0,3,0.5,0)
    knb.Size = UDim2.fromOffset(16,16)
    knb.BackgroundColor3 = T.text
    knb.BorderSizePixel = 0
    knb.Parent = trk
    corner(knb,8)

    local state = flags[key] or false
    local function paint(animate)
        local ti = animate and TweenInfo.new(0.2,Enum.EasingStyle.Quint) or TweenInfo.new(0)
        TweenService:Create(trk,ti,{BackgroundColor3=state and T.accent or T.off}):Play()
        TweenService:Create(knb,ti,{Position=UDim2.new(0,state and 23 or 3,0.5,0)}):Play()
        TweenService:Create(lbl,ti,{TextColor3=state and T.text or T.sub}):Play()
    end
    paint(false)

    row.MouseEnter:Connect(function()
        TweenService:Create(row,TweenInfo.new(0.15),{BackgroundColor3=T.panelHi}):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row,TweenInfo.new(0.15),{BackgroundColor3=T.inset}):Play()
    end)
    row.MouseButton1Click:Connect(function()
        state = not state
        flags[key] = state
        paint(true)
        if onToggle then onToggle(state) end
    end)
    return row
end

local function buildAction(parent, text, cb, order, danger, customColor)
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1,0,0,34)
    row.BackgroundColor3 = customColor or T.inset
    row.AutoButtonColor = false
    row.Text = ""
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent
    corner(row,8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.fromScale(1,1)
    lbl.Font = customColor and FONT_BOLD or FONT
    lbl.TextSize = MOBILE and 12 or 13
    lbl.TextColor3 = customColor and T.text or (danger and T.danger or T.sub)
    lbl.Text = text
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.Parent = row

    row.MouseEnter:Connect(function()
        TweenService:Create(row,TweenInfo.new(0.15),{BackgroundColor3=T.panelHi}):Play()
        TweenService:Create(lbl,TweenInfo.new(0.15),{TextColor3=T.text}):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenService:Create(row,TweenInfo.new(0.15),{BackgroundColor3=customColor or T.inset}):Play()
        TweenService:Create(lbl,TweenInfo.new(0.15),{TextColor3=customColor and T.text or (danger and T.danger or T.sub)}):Play()
    end)
    row.MouseButton1Click:Connect(cb)
    return row
end

local function buildSlider(parent, text, min, max, default, cb, order)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1,0,0,48)
    row.BackgroundColor3 = T.inset
    row.BorderSizePixel = 0
    row.LayoutOrder = order
    row.Parent = parent
    corner(row,8)

    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.Position = UDim2.fromOffset(12,4)
    lbl.Size = UDim2.new(1,-70,0,16)
    lbl.Font = FONT
    lbl.TextSize = MOBILE and 12 or 13
    lbl.TextColor3 = T.sub
    lbl.Text = text
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local val = Instance.new("TextLabel")
    val.BackgroundTransparency = 1
    val.AnchorPoint = Vector2.new(1,0)
    val.Position = UDim2.new(1,-12,0,4)
    val.Size = UDim2.fromOffset(52,16)
    val.Font = FONT_BOLD
    val.TextSize = MOBILE and 12 or 13
    val.TextColor3 = T.accent
    val.Text = tostring(default)
    val.TextXAlignment = Enum.TextXAlignment.Right
    val.Parent = row

    local bar = Instance.new("Frame")
    bar.Position = UDim2.fromOffset(12,30)
    bar.Size = UDim2.new(1,-24,0,8)
    bar.BackgroundColor3 = T.off
    bar.BorderSizePixel = 0
    bar.Parent = row
    corner(bar,4)

    local rel = (default-min)/math.max(max-min,1)
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(rel,0,1,0)
    fill.BackgroundColor3 = T.accent
    fill.BorderSizePixel = 0
    fill.Parent = bar
    corner(fill,4)
    grad(fill,T.accent,Color3.fromRGB(80,190,255),0)

    local knob = Instance.new("Frame")
    knob.AnchorPoint = Vector2.new(0.5,0.5)
    knob.Position = UDim2.new(rel,0,0.5,0)
    knob.Size = UDim2.fromOffset(16,16)
    knob.BackgroundColor3 = T.text
    knob.BorderSizePixel = 0
    knob.Parent = bar
    corner(knob,8)

    local hit = Instance.new("TextButton")
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.AutoButtonColor = false
    hit.Position = UDim2.new(0,0,0,22)
    hit.Size = UDim2.new(1,0,0,26)
    hit.Parent = row

    local dragging=false
    local function apply(px)
        local r=math.clamp((px-bar.AbsolutePosition.X)/math.max(bar.AbsoluteSize.X,1),0,1)
        local v=math.floor(min+(max-min)*r+0.5)
        fill.Size=UDim2.new(r,0,1,0)
        knob.Position=UDim2.new(r,0,0.5,0)
        val.Text=tostring(v)
        cb(v)
    end
    hit.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; apply(i.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then apply(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end
    end)
    return row
end

local function buildSection(parent, txt, order)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1,0,0,22)
    f.BackgroundTransparency = 1
    f.LayoutOrder = order
    f.Parent = parent
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.fromOffset(6,0)
    l.Size = UDim2.new(1,-12,1,0)
    l.Font = FONT_BOLD
    l.TextSize = 11
    l.TextColor3 = T.dim
    l.Text = txt
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = f
    return f
end

do
    local p=PAGES.sheriff.scroll
    buildSection(p,"AIM",1)
    buildToggle(p,"Silent Aim","silentAim",2)
    buildSection(p,"GUN",3)
    buildToggle(p,"Auto Grab Gun","autoGun",4)
    buildAction(p,"Grab Gun Now",function()
        if findWeapon("Gun") then return end
        if not (droppedGun or findDroppedGun()) then return end
        grabGunOnce()
    end,5)
end
do
    local p=PAGES.murder.scroll
    buildSection(p,"MAIN",1)
    buildToggle(p,"Auto Kill (role based)","autoKill",2)
    buildSection(p,"KNIFE",3)
    buildToggle(p,"Knife Through Walls","knifeWalls",4)
    buildToggle(p,"Instant Knife Throw","instantKnife",5)
end
do
    local p=PAGES.farm.scroll
    buildSection(p,"COINS",1)
    buildToggle(p,"Auto Collect Coins","autoCoins",2,function(on)
        if on then
            prevNoclip = flags.noclip
            setNoclip(true)
        else
            if not prevNoclip then setNoclip(false) end
        end
    end)
    buildSlider(p,"Coin Farm Speed",1,200,16,function(v) flags.coinSpeed=v end,3)
    buildAction(p,"Teleport To Nearest Coin",function()
        local hrp=getHRP(LocalPlayer.Character); if not hrp then return end
        local pool=coinCache
        if #pool==0 then pool=freshCoins() end
        local best,bd
        for _,c in ipairs(pool) do
            if c.Parent and not coinTaken(c) then
                local d=(c.Position-hrp.Position).Magnitude
                if not bd or d<bd then bd,best=d,c end
            end
        end
        if best then
            local now = os.clock()
            if now - (CoinTPLast or -10) < 0.5 then return end
            CoinTPLast = now
            doTP(best.Position)
        end
    end,4)
end

do
    local p=PAGES.fling.scroll

    buildSection(p,"SELECT TARGET",1)

    local selectedPlayer = nil
    local dropdownOpen = false

    local dropdownBox = Instance.new("Frame")
    dropdownBox.Size = UDim2.new(1,0,0,0)
    dropdownBox.BackgroundTransparency = 1
    dropdownBox.ClipsDescendants = true
    dropdownBox.AutomaticSize = Enum.AutomaticSize.None
    dropdownBox.LayoutOrder = 2
    dropdownBox.Parent = p

    local dropLayout = Instance.new("UIListLayout")
    dropLayout.Padding = UDim.new(0,4)
    dropLayout.SortOrder = Enum.SortOrder.LayoutOrder
    dropLayout.Parent = dropdownBox

    local dropdownHeader = Instance.new("TextButton")
    dropdownHeader.Size = UDim2.new(1,0,0,38)
    dropdownHeader.BackgroundColor3 = T.inset
    dropdownHeader.BorderSizePixel = 0
    dropdownHeader.Text = ""
    dropdownHeader.AutoButtonColor = false
    dropdownHeader.LayoutOrder = 1
    dropdownHeader.Parent = dropdownBox
    corner(dropdownHeader,8)

    local headerLbl = Instance.new("TextLabel")
    headerLbl.BackgroundTransparency = 1
    headerLbl.Position = UDim2.fromOffset(12,0)
    headerLbl.Size = UDim2.new(1,-40,1,0)
    headerLbl.Font = FONT
    headerLbl.TextSize = MOBILE and 12 or 13
    headerLbl.TextColor3 = T.sub
    headerLbl.Text = "Select a player..."
    headerLbl.TextXAlignment = Enum.TextXAlignment.Left
    headerLbl.Parent = dropdownHeader

    local arrowLbl = Instance.new("TextLabel")
    arrowLbl.BackgroundTransparency = 1
    arrowLbl.AnchorPoint = Vector2.new(1,0.5)
    arrowLbl.Position = UDim2.new(1,-12,0.5,0)
    arrowLbl.Size = UDim2.fromOffset(20,20)
    arrowLbl.Font = FONT_BOLD
    arrowLbl.TextSize = 14
    arrowLbl.TextColor3 = T.dim
    arrowLbl.Text = "v"
    arrowLbl.TextXAlignment = Enum.TextXAlignment.Center
    arrowLbl.Parent = dropdownHeader

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1,0,0,180)
    listFrame.BackgroundColor3 = T.inset
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 3
    listFrame.ScrollBarImageColor3 = T.accent
    listFrame.CanvasSize = UDim2.new(0,0,0,0)
    listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
    listFrame.ScrollingEnabled = true
    listFrame.LayoutOrder = 2
    listFrame.Visible = false
    listFrame.Parent = dropdownBox
    corner(listFrame,8)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0,3)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = listFrame

    local listPad = Instance.new("UIPadding")
    listPad.PaddingTop = UDim.new(0,4)
    listPad.PaddingBottom = UDim.new(0,4)
    listPad.PaddingLeft = UDim.new(0,4)
    listPad.PaddingRight = UDim.new(0,4)
    listPad.Parent = listFrame

    local function setOpen(open)
        dropdownOpen = open
        listFrame.Visible = open
        arrowLbl.Text = open and "^" or "v"
        local target = open and 222 or 38
        TweenService:Create(dropdownBox, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
            {Size = UDim2.new(1,0,0,target)}):Play()
    end
    setOpen(false)

    dropdownHeader.MouseButton1Click:Connect(function()
        setOpen(not dropdownOpen)
    end)
    dropdownHeader.MouseEnter:Connect(function()
        TweenService:Create(dropdownHeader,TweenInfo.new(0.12),{BackgroundColor3=T.panelHi}):Play()
    end)
    dropdownHeader.MouseLeave:Connect(function()
        TweenService:Create(dropdownHeader,TweenInfo.new(0.12),{BackgroundColor3=T.inset}):Play()
    end)

    local playerRows = {}

    local function updateList()
        for _, row in pairs(playerRows) do row:Destroy() end
        playerRows = {}

        local idx = 0
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                idx = idx + 1
                local isSelected = (plr == selectedPlayer)

                local row = Instance.new("TextButton")
                row.Size = UDim2.new(1,-4,0,28)
                row.BackgroundColor3 = isSelected and T.accent or T.panel
                row.BorderSizePixel = 0
                row.Text = ""
                row.AutoButtonColor = false
                row.LayoutOrder = idx
                row.Parent = listFrame
                corner(row, 6)

                local nameLbl = Instance.new("TextLabel")
                nameLbl.BackgroundTransparency = 1
                nameLbl.Size = UDim2.new(1,-16,1,0)
                nameLbl.Position = UDim2.fromOffset(10,0)
                nameLbl.Font = FONT
                nameLbl.TextSize = MOBILE and 12 or 13
                nameLbl.TextColor3 = isSelected and T.text or T.sub
                nameLbl.Text = plr.Name
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.Parent = row

                row.MouseButton1Click:Connect(function()
                    selectedPlayer = plr
                    headerLbl.Text = "Selected: " .. plr.Name
                    headerLbl.TextColor3 = T.accent
                    for _, r in ipairs(listFrame:GetChildren()) do
                        if r:IsA("TextButton") then
                            r.BackgroundColor3 = T.panel
                            local l = r:FindFirstChildOfClass("TextLabel")
                            if l then l.TextColor3 = T.sub end
                        end
                    end
                    row.BackgroundColor3 = T.accent
                    nameLbl.TextColor3 = T.text
                    task.wait(0.12)
                    setOpen(false)
                end)

                row.MouseEnter:Connect(function()
                    if plr ~= selectedPlayer then
                        TweenService:Create(row,TweenInfo.new(0.12),{BackgroundColor3=T.panelHi}):Play()
                    end
                end)
                row.MouseLeave:Connect(function()
                    if plr ~= selectedPlayer then
                        TweenService:Create(row,TweenInfo.new(0.12),{BackgroundColor3=T.panel}):Play()
                    end
                end)

                table.insert(playerRows, row)
            end
        end

        if #playerRows == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1,-4,0,28)
            empty.BackgroundTransparency = 1
            empty.Font = FONT_REG
            empty.TextSize = 12
            empty.TextColor3 = T.dim
            empty.Text = "No other players"
            empty.TextXAlignment = Enum.TextXAlignment.Center
            empty.LayoutOrder = 0
            empty.Parent = listFrame
            table.insert(playerRows, empty)
        end

        if selectedPlayer and not Players:FindFirstChild(selectedPlayer.Name) then
            selectedPlayer = nil
            headerLbl.Text = "Select a player..."
            headerLbl.TextColor3 = T.sub
        end
    end

    updateList()
    Players.PlayerAdded:Connect(function() task.wait(0.15); updateList() end)
    Players.PlayerRemoving:Connect(function() task.wait(0.15); updateList() end)

    buildSection(p,"ACTION",3)

    buildAction(p,"Fling Selected",function()
        if not selectedPlayer then return end
        if flinging then return end
        if not selectedPlayer.Character then return end
        startFling(selectedPlayer)
    end,4,false,T.accent)

    buildAction(p,"Stop Fling",function()
        stopFling()
    end,5,true,T.danger)
end

do
    local p = PAGES.servers.scroll

    local introPanel = Instance.new("Frame")
    introPanel.Size = UDim2.new(1,0,0,140)
    introPanel.BackgroundColor3 = T.inset
    introPanel.BorderSizePixel = 0
    introPanel.LayoutOrder = 1
    introPanel.Parent = p
    corner(introPanel,10)

    local introLbl = Instance.new("TextLabel")
    introLbl.BackgroundTransparency = 1
    introLbl.Position = UDim2.fromOffset(14,14)
    introLbl.Size = UDim2.new(1,-28,0,80)
    introLbl.Font = FONT
    introLbl.TextSize = MOBILE and 12 or 13
    introLbl.TextColor3 = T.text
    introLbl.TextWrapped = true
    introLbl.TextXAlignment = Enum.TextXAlignment.Left
    introLbl.TextYAlignment = Enum.TextYAlignment.Top
    introLbl.Text = "Here you can see every other server where a player uses J3rry Hub (this script)."
    introLbl.Parent = introPanel

    local okBtn = Instance.new("TextButton")
    okBtn.AnchorPoint = Vector2.new(0.5,0)
    okBtn.Position = UDim2.new(0.5,0,0,100)
    okBtn.Size = UDim2.fromOffset(120,30)
    okBtn.BackgroundColor3 = T.accent
    okBtn.BorderSizePixel = 0
    okBtn.Text = "OK"
    okBtn.TextColor3 = Color3.fromRGB(255,255,255)
    okBtn.Font = FONT_BOLD
    okBtn.TextSize = MOBILE and 12 or 13
    okBtn.AutoButtonColor = false
    okBtn.Parent = introPanel
    corner(okBtn,7)
    okBtn.MouseEnter:Connect(function()
        TweenService:Create(okBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(180,120,255)}):Play()
    end)
    okBtn.MouseLeave:Connect(function()
        TweenService:Create(okBtn,TweenInfo.new(0.12),{BackgroundColor3=T.accent}):Play()
    end)

    local contentPanel = Instance.new("Frame")
    contentPanel.Size = UDim2.new(1,0,0,380)
    contentPanel.BackgroundTransparency = 1
    contentPanel.LayoutOrder = 2
    contentPanel.Visible = false
    contentPanel.Parent = p

    local contentLayout = Instance.new("UIListLayout")
    contentLayout.Padding = UDim.new(0,6)
    contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
    contentLayout.Parent = contentPanel

    local statusLbl = Instance.new("TextLabel")
    statusLbl.BackgroundTransparency = 1
    statusLbl.Size = UDim2.new(1,0,0,20)
    statusLbl.Font = FONT
    statusLbl.TextSize = MOBILE and 11 or 12
    statusLbl.TextColor3 = T.dim
    statusLbl.Text = "Loading..."
    statusLbl.TextXAlignment = Enum.TextXAlignment.Left
    statusLbl.LayoutOrder = 1
    statusLbl.Parent = contentPanel

    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(1,0,0,34)
    refreshBtn.BackgroundColor3 = T.accent
    refreshBtn.BorderSizePixel = 0
    refreshBtn.Text = "Refresh"
    refreshBtn.TextColor3 = Color3.fromRGB(255,255,255)
    refreshBtn.Font = FONT_BOLD
    refreshBtn.TextSize = MOBILE and 12 or 13
    refreshBtn.AutoButtonColor = false
    refreshBtn.LayoutOrder = 2
    refreshBtn.Parent = contentPanel
    corner(refreshBtn,8)
    refreshBtn.MouseEnter:Connect(function()
        TweenService:Create(refreshBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(180,120,255)}):Play()
    end)
    refreshBtn.MouseLeave:Connect(function()
        TweenService:Create(refreshBtn,TweenInfo.new(0.12),{BackgroundColor3=T.accent}):Play()
    end)

    local serverList = Instance.new("ScrollingFrame")
    serverList.Size = UDim2.new(1,0,0,320)
    serverList.BackgroundTransparency = 1
    serverList.BorderSizePixel = 0
    serverList.ScrollBarThickness = 3
    serverList.ScrollBarImageColor3 = T.accent
    serverList.CanvasSize = UDim2.new(0,0,0,0)
    serverList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    serverList.ScrollingDirection = Enum.ScrollingDirection.Y
    serverList.ScrollingEnabled = true
    serverList.LayoutOrder = 3
    serverList.Parent = contentPanel

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0,6)
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = serverList

    local function clearList()
        for _, c in ipairs(serverList:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") or c:IsA("Frame") then c:Destroy() end
        end
    end

    local function renderServers(list)
        clearList()
        local shown = 0
        for _, s in ipairs(list or {}) do
            if s.jobId and s.jobId ~= game.JobId then
                shown = shown + 1
                local card = Instance.new("Frame")
                card.Size = UDim2.new(1,0,0,52)
                card.BackgroundColor3 = T.inset
                card.BorderSizePixel = 0
                card.LayoutOrder = shown
                card.Parent = serverList
                corner(card,8)

                local nameLbl = Instance.new("TextLabel")
                nameLbl.BackgroundTransparency = 1
                nameLbl.Position = UDim2.fromOffset(12,6)
                nameLbl.Size = UDim2.new(1,-110,0,18)
                nameLbl.Font = FONT_BOLD
                nameLbl.TextSize = MOBILE and 12 or 13
                nameLbl.TextColor3 = T.text
                nameLbl.Text = tostring(s.username or "?")
                nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                nameLbl.Parent = card

                local subLbl = Instance.new("TextLabel")
                subLbl.BackgroundTransparency = 1
                subLbl.Position = UDim2.fromOffset(12,26)
                subLbl.Size = UDim2.new(1,-110,0,16)
                subLbl.Font = FONT_REG
                subLbl.TextSize = MOBILE and 11 or 12
                subLbl.TextColor3 = T.sub
                subLbl.Text = tostring(s.players or 0) .. " / " .. tostring(s.maxPlayers or 0) .. " players"
                subLbl.TextXAlignment = Enum.TextXAlignment.Left
                subLbl.Parent = card

                local joinBtn = Instance.new("TextButton")
                joinBtn.AnchorPoint = Vector2.new(1,0.5)
                joinBtn.Position = UDim2.new(1,-10,0.5,0)
                joinBtn.Size = UDim2.fromOffset(80,30)
                joinBtn.BackgroundColor3 = T.accent
                joinBtn.BorderSizePixel = 0
                joinBtn.Text = "Join"
                joinBtn.TextColor3 = Color3.fromRGB(255,255,255)
                joinBtn.Font = FONT_BOLD
                joinBtn.TextSize = MOBILE and 12 or 13
                joinBtn.AutoButtonColor = false
                joinBtn.Parent = card
                corner(joinBtn,7)

                joinBtn.MouseEnter:Connect(function()
                    TweenService:Create(joinBtn,TweenInfo.new(0.12),{BackgroundColor3=Color3.fromRGB(180,120,255)}):Play()
                end)
                joinBtn.MouseLeave:Connect(function()
                    TweenService:Create(joinBtn,TweenInfo.new(0.12),{BackgroundColor3=T.accent}):Play()
                end)

                joinBtn.MouseButton1Click:Connect(function()
                    local targetJobId = s.jobId
                    local targetPlaceId = s.placeId

                    if not targetJobId or targetJobId == "" then
                        joinBtn.Text = "Failed"
                        joinBtn.BackgroundColor3 = T.danger
                        task.delay(2, function()
                            if joinBtn and joinBtn.Parent then
                                joinBtn.Text = "Join"
                                joinBtn.BackgroundColor3 = T.accent
                            end
                        end)
                        return
                    end

                    if not targetPlaceId then
                        targetPlaceId = game.PlaceId
                    end

                    joinBtn.Text = "Joining..."
                    joinBtn.Active = false
                    joinBtn.BackgroundColor3 = T.panelHi
                    if statusLbl then
                        statusLbl.Text = "Trying to join " .. tostring(s.username or "?") .. "..."
                    end

                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(
                            targetPlaceId,
                            tostring(targetJobId),
                            LocalPlayer
                        )
                    end)
                end)
            end
        end

        if shown == 0 then
            statusLbl.Text = ""
            local empty = Instance.new("TextLabel")
            empty.BackgroundTransparency = 1
            empty.Size = UDim2.new(1,0,0,30)
            empty.Font = FONT_BOLD
            empty.TextSize = 14
            empty.TextColor3 = T.dim
            empty.Text = "No active servers"
            empty.TextXAlignment = Enum.TextXAlignment.Center
            empty.LayoutOrder = 0
            empty.Parent = serverList
        else
            statusLbl.Text = tostring(shown) .. " active"
        end
    end

    local function refreshServers()
        statusLbl.Text = "Loading..."
        task.spawn(function()
            local body = httpGet(API_URL .. "?action=list")
            if not body then
                statusLbl.Text = "Failed to load servers"
                return
            end
            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok or type(data) ~= "table" or not data.servers then
                statusLbl.Text = "Invalid response"
                return
            end
            renderServers(data.servers)
        end)
    end

    refreshBtn.MouseButton1Click:Connect(function() refreshServers() end)

    okBtn.MouseButton1Click:Connect(function()
        introPanel.Visible = false
        contentPanel.Visible = true
        refreshServers()
    end)
end

do
    local p=PAGES.teleport.scroll
    buildSection(p,"PLAYERS",1)
    buildAction(p,"Teleport To Murderer",function()
        local m=findMurderer()
        if not m then return end
        local hrp=getHRP(m.Character)
        if hrp then doTP(hrp.Position) end
    end,2)
    buildAction(p,"Teleport To Sheriff",function()
        local s=findSheriff()
        if not s then return end
        local hrp=getHRP(s.Character)
        if hrp then doTP(hrp.Position) end
    end,3)
end
do
    local p=PAGES.player.scroll
    buildSection(p,"MOVEMENT",1)
    buildToggle(p,"Fly","fly",2)
    buildSlider(p,"Fly Speed",20,250,60,function(v) flags.flySpeed=v end,3)
    buildToggle(p,"Noclip","noclip",4)
    buildToggle(p,"Infinite Jump","infJump",5)
    buildSection(p,"SPEED",6)
    buildToggle(p,"Walk Speed","walkSpeed",7)
    buildSlider(p,"Walk Speed Value",16,120,16,function(v) flags.walkSpeedValue=v; if flags.walkSpeed then applyWalkSpeed() end end,8)
    buildSection(p,"ACTIONS",9)
    buildAction(p,"Reset Character",function()
        local h=LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then h.Health=0 end
    end,10,true)
end
do
    local p=PAGES.esp.scroll
    buildSection(p,"ESP BY ROLE",1)
    buildToggle(p,"Innocent ESP","espInnocent",2)
    buildToggle(p,"Sheriff ESP","espSheriff",3)
    buildToggle(p,"Murderer ESP","espMurderer",4)
end

task.spawn(function()
    local lastFly=false
    local lastWS=false
    while true do
        if flags.fly ~= lastFly then
            lastFly=flags.fly
            if flags.fly then startFly() else stopFly() end
        end
        if flags.walkSpeed ~= lastWS then
            lastWS=flags.walkSpeed
            if flags.walkSpeed then
                applyWalkSpeed()
            else
                local ch=LocalPlayer.Character
                local hum=ch and ch:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed=16 end
            end
        elseif flags.walkSpeed then
            applyWalkSpeed()
        end
        task.wait(0.1)
    end
end)

local BUBBLE
local lastBubblePos = nil
local function showBubble()
    if BUBBLE then BUBBLE:Destroy() end
    BUBBLE = Instance.new("TextButton")
    BUBBLE.Size = UDim2.fromOffset(56,56)
    if lastBubblePos then
        BUBBLE.Position = lastBubblePos
    else
        BUBBLE.Position = UDim2.fromOffset(24, math.max(60, Camera.ViewportSize.Y/2 - 28))
    end
    BUBBLE.BackgroundColor3 = T.accent
    BUBBLE.Text = "JH"
    BUBBLE.TextColor3 = Color3.fromRGB(255,255,255)
    BUBBLE.Font = FONT_BOLD
    BUBBLE.TextSize = 22
    BUBBLE.AutoButtonColor = false
    BUBBLE.BorderSizePixel = 0
    BUBBLE.Active = true
    BUBBLE.Draggable = true
    BUBBLE.Parent = screenGui
    corner(BUBBLE,28)
    grad(BUBBLE,T.accent,Color3.fromRGB(80,190,255),135)

    local glow = Instance.new("UIStroke")
    glow.Color = Color3.fromRGB(180,120,255)
    glow.Thickness = 2
    glow.Transparency = 0.4
    glow.Parent = BUBBLE

    local pulse = TweenService:Create(BUBBLE,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Size=UDim2.fromOffset(62,62)})
    pulse:Play()

    local gp = TweenService:Create(glow,
        TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Transparency=0.1})
    gp:Play()

    BUBBLE.MouseEnter:Connect(function()
        TweenService:Create(BUBBLE,TweenInfo.new(0.15),{BackgroundColor3=Color3.fromRGB(180,120,255)}):Play()
    end)
    BUBBLE.MouseLeave:Connect(function()
        TweenService:Create(BUBBLE,TweenInfo.new(0.15),{BackgroundColor3=T.accent}):Play()
    end)

    BUBBLE.MouseButton1Click:Connect(function()
        lastBubblePos = BUBBLE.Position
        pulse:Cancel(); gp:Cancel()
        local fromPos = BUBBLE.AbsolutePosition
        BUBBLE:Destroy(); BUBBLE=nil
        root.Visible = true
        root.Size = UDim2.fromOffset(56,56)
        root.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
        root.BackgroundTransparency = 1
        TweenService:Create(root,TweenInfo.new(0.32,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),
            {Size=UDim2.fromOffset(W,H),BackgroundTransparency=0}):Play()
        TweenService:Create(root,TweenInfo.new(0.32,Enum.EasingStyle.Quint,Enum.EasingDirection.Out),
            {Position=UDim2.new(0.5,-W/2,0.5,-H/2)}):Play()
    end)
end

local function collapse()
    root.Visible = false
    showBubble()
end

local function destroyAll()
    if BUBBLE then BUBBLE:Destroy(); BUBBLE=nil end
    for p in pairs(espStore) do clearEsp(p) end
    pcall(function() stopFling() end)
    pcall(function() screenGui:Destroy() end)
    pcall(function() if ESP_FOLDER then ESP_FOLDER:Destroy() end end)
    pcall(function() stopFly() end)
    pcall(function() setNoclip(false) end)
    pcall(function() LocalPlayer.CameraMode = Enum.CameraMode.Classic end)
    flags.fly=false
    flags.noclip=false
    flags.silentAim=false
end

minBtn.MouseButton1Click:Connect(collapse)
closeBtn.MouseButton1Click:Connect(destroyAll)

selectTab("sheriff")

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    if flags.noclip then setNoclip(true) end
    if flags.fly then stopFly(); startFly() end
    if flags.walkSpeed then applyWalkSpeed() end
end)