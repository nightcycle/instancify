--CJ_Oyer, 2022
--[=[
	A module used to provide instance based controls for rapid prototyping and inter-script communication with objects.
	@class Instancify
]=]

local collectionService = game:GetService("CollectionService")
local runService = game:GetService("RunService")
local replicatedStorage = game:GetService("ReplicatedStorage")

local maidConstructor = require(script.Parent:WaitForChild("maid"))
local rx = require(script.Parent:WaitForChild("rx"))
local signalConstructor = require(script.Parent:WaitForChild("signal"))

local module = {}
local attributeTypes = {
    string = true,
    boolean = true,
    number = true,
    UDim = true,
    UDim2 = true,
    BrickColor = true,
    Color3 = true,
    Vector2 = true,
    Vector3 = true,
    NumberSequence = true,
    ColorSequence = true,
    NumberRange = true,
    Rect = true,
}

local valueTypes = {
    boolean = "BoolValue",
    BrickColor = "BrickColorValue",
    CFrame = "CFrameValue",
    Color3 = "Color3Value",
    number = "NumberValue",
    Instance = "ObjectValue",
    Ray = "RayValue",
    string = "StringValue",
    Vector3 = "Vector3Value",
}

local metaTags = {
    __index = true,
    __newindex = true,
    __call = true,
    __concat = true,
    __unm = true,
    __add = true,
    __sub = true,
    __mul = true,
    __div = true,
    __mod = true,
    __pow = true,
    __tostring = true,
    __metatable = true,
    __eq = true,
    __lt = true,
    __le = true,
    __mode = true,
    __len = true,
}

function isPrivate(key)
    return string.sub(key, 1, 1) == "_"
end

function handleValue(inst, onChangeFunction, propName, propValue, maid, events, replicatedPlayer)
    local propType = typeof(propValue)
    local replicator = inst:FindFirstChild("_Replicator") 
    if attributeTypes[propType] then
        inst:SetAttribute(propName, propValue)
        maid["_property"..propName] = inst:GetAttributeChangedSignal(propName):Connect(function()
            if events["On"..propName] then
                events:Fire(propValue)
            end
            if replicatedPlayer and replicator then
                if runService:IsServer() then
                    replicator:FireClient(replicatedPlayer, "Property", propName, propValue)
                else
                    replicator:FireServer("Property", propName, propValue)
                end
            end
            onChangeFunction(propName, inst:GetAttribute(propName))
        end)
    elseif valueTypes[propType] then
        local propValueInst = inst:FindFirstChild(propName)
        if not propValueInst then
            propValueInst = Instance.new(valueTypes[propType])
            propValueInst.Name = propName
            propValueInst.Parent = inst
            maid:GiveTask(propValueInst)
        end
        propValueInst.Value = propValue
        if propType == "Instance" then
            collectionService:AddTag(propValueInst, "IsActuallyInstance")
        end
        maid["_attribute"..propName] = propValueInst:GetPropertyChangedSignal("Value"):Connect(function()
            if events["On"..propName] then
                events:Fire(propValue)
            end
            if replicatedPlayer and replicator then
                if runService:IsServer() then
                    replicator:FireClient(replicatedPlayer, "Property", propName, propValue)
                else
                    replicator:FireServer("Property", propName, propValue)
                end
            end
            onChangeFunction(propName, propValueInst.Value)
        end)
    end
end

function handleObject(inst, propName, propValue, maid)
    local currentInst = propValue.Instance or inst:FindFirstChild(propName)
    local isInstancified = false
    if runService:IsClient() then
        if collectionService:HasTag(inst, "ClientInstancified") then isInstancified = true end
    else
        if collectionService:HasTag(inst, "ServerInstancified") then isInstancified = true end
    end
    if currentInst and not isInstancified then
        module.set(propValue, currentInst)
        return currentInst
    elseif not currentInst then
        local newInst = module.new(propValue, propName, inst)
        maid["_propObject_"..propName] = newInst
        return newInst
    end
end

function updateProperties(inst, properties, maid, events, replicatedPlayer)
    for propName, propValue in pairs(properties) do
        local propType = typeof(propValue)
        if propType == "table" then
            if propValue.Value or propValue.get then
                handleValue(inst, function(k, v)
                    if propValue.Value then
                        propValue.Value = v
                    elseif propValue.get then
                        propValue:set(v)
                    end
                end, propName, propValue, maid, events, replicatedPlayer)
            -- else
                -- handleObject(inst, propName, propValue, maid)
            end
        else
            handleValue(inst, function(k, v)
                properties[k] = v
            end, propName, propValue, maid, events, replicatedPlayer)
        end
    end
end

--[=[
    @function get
    This takes properties, bindableEvents, and bindableFunctions to construct a table interface that can act as a pseudo object.
    @within Instancify
    @return Object
]=]

-- function setUpPropertySignals(tabl, updateFunc)
--     local meta = getmetatable(tabl)
--     local baseFunction = function(t, k, v)
        
--     end
--     if meta.__newindex == nil then
--         baseFunction = meta.__newindex
--     end
--     meta.__newindex = function()
        
--     end
-- end

function module.get(inst)
    if runService:IsClient() then
        if not collectionService:HasTag(inst, "ClientInstancified") then warn("No instance found at ", inst) end
    else
        if not collectionService:HasTag(inst, "ServerInstancified") then warn("No instance found at ", inst) end
    end


    local self = {}
    local maid = maidConstructor.new()
    self._maid = maid

    -- local properties = {}
    local valueBases = {}
    local attributes = {}
    for i, v in ipairs(inst:GetChildren()) do
        local k = v.Name
        -- print(k.." classname", v.ClassName)
        if v.ClassName == "BindableFunction" then
            self[k] = function(...)
                if k == "Destroy" then maid:Destroy() end
                v:Invoke(...)
            end
        elseif v.ClassName == "BindableEvent" then
            self[k] = v
        elseif v:IsA("ValueBase") then
            -- print("Setting attribute ", k, v)
            valueBases[k] = v
            if v.ClassName ~= "ObjectValue" or collectionService:HasTag(v, "IsActuallyInstance") then
                self[k] = v.Value
                maid["val_"..k] = v:GetPropertyChangedSignal("Value"):Connect(function()
                    self[k] = v.Value
                end)
            -- else
            --     self[k] = module.get(v)
            --     maid["val_"..k] = v:GetPropertyChangedSignal("Value"):Connect(function()
            --         self[k] = module.get(v)
            --     end)
            end
        end
    end
    local objectObserver = rx.of(self)
    maid:GiveTask(objectObserver:Subscribe(function()
        for k, value in pairs(valueBases) do
            if value.ClassName ~= "ObjectValue" or collectionService:HasTag(value, "IsActuallyInstance") then
                valueBases[k].Value = self[k]
            -- else
            --     valueBases[k].Value = handleObject(inst, k, self[k], maid)
            end
        end
        for k, aV in pairs(attributes) do
            if attributes[k] ~= nil then
                inst:SetAttribute(k, self[k])
            end
        end
    end))

    for k, v in pairs(inst:GetAttributes()) do
        attributes[k] = v
        self[k] = v
        maid["atr_"..k] = inst:GetAttributeChangedSignal(k):Connect(function()
            self[k] = inst:GetAttribute(k)
        end)
    end

    maid:GiveTask(inst.Destroying:Connect(function()
        maid:Destroy()
    end))
    maid:GiveTask(self)
    return self
end

--[=[
    @function new
    This will create a new instance, rather than converting an existing one.
    @param self Object -- the object being turned into an instance
    @param name string -- the name of the new instance
    @param parent Instance -- what the new Instance will be parented to
    @within Instancify
    @return Instance
]=]
function module.new(self, name, parent, createFunctionEvents: boolean | nil, replicationPlayer: Player | nil)
    -- logger:AtInfo():Log("Creating new object instance")
    local objInstance = Instance.new("Configuration", parent or workspace)
    objInstance.Name = name or "Object"
    module.set(self, objInstance, createFunctionEvents, replicationPlayer)
    return objInstance
end

--[=[
    @function set
    @param self Object -- the object being turned into an instance
    @param inst Instance -- the instance that the object will be bound to
    @within Instancify
    @return nil
]=]
function module.set(self: table, inst: Instance,
    createFunctionEvents: boolean | nil, replicationPlayer: Player | nil)
    if runService:IsClient() then
        if collectionService:HasTag(inst, "ClientInstancified") then warn("Already instancified") return end
    else
        if collectionService:HasTag(inst, "ServerInstancified") then warn("Already instancified") return end
    end

    -- logger:AtInfo():Log("Applying object to instance")


    local maid = maidConstructor.new()
    if self._maid then
        self._maid:GiveTask(maid)
    end

    local function assembleObject(tabl)
        local object = {}
        local meta = getmetatable(tabl)
        if meta then
            meta = assembleObject(meta)
        end
        for k, v in pairs(getmetatable(tabl) or {}) do
            if not metaTags[k] then
                object[k] = v
            end
        end
        for k, v in pairs(tabl) do
            object[k] = v
        end
        return object
    end

    local fullObject = assembleObject(self)

    -- local properties = {}
    local functions = {}
    local events = {}
    for k, v in pairs(fullObject) do
        if not isPrivate(k) then
            if typeof(v) == "function" then
                functions[k] = v
                local eventName = "On"..k
                if createFunctionEvents and self[eventName] == nil then
                    local signal = signalConstructor.new()
                    self[eventName] = signal
                    maid["sig_"..eventName] = signal
                    events[eventName] = signal
                end
            elseif typeof(v) == "RBXScriptSignal" then
                events[k] = v
            elseif typeof(v) == "table" then
                if v.ClassName == "Observable" then
                    events[k] = v
                elseif v.ClassName == "Signal" then
                    events[k] = v
                end
            else
                self[k] = v
            end
        end
    end

    local replicatedEvent
    -- print("Rep player", replicationPlayer)
    if replicationPlayer ~= nil then
        -- print("Rep A")
        if runService:IsServer() then
            -- print("Rep B")
            replicatedEvent = Instance.new("RemoteEvent", inst)
            replicatedEvent.Name = "_Replicator"
            self._maid:GiveTask(replicatedEvent.OnServerEvent:Connect(function(p, changeType, key, ...)
                -- print("Server", p, changeType, key, ...)
                if p == replicationPlayer then
                    -- print("Key", key, self)
                    if changeType == "Events" then
                        inst:FindFirstChild(key):Fire(...)
                    elseif changeType == "Properties" then
                        self[key] = ...
                    elseif changeType == "Function" then
                        self[key](self, ...)
                        if createFunctionEvents then
                            inst:FindFirstChild("On"..key):Fire()
                        end
                        -- inst:FindFirstChild(key):Invoke(...)
                    end
                end
            end))
        else
            -- print("Rep B2")
            replicatedEvent = inst:WaitForChild("_Replicator")
            self._maid:GiveTask(replicatedEvent.OnClientEvent:Connect(function(changeType, key, ...)
                -- print("Client", changeType, key, ...)
                if changeType == "Events" then
                    inst:FindFirstChild(key):Fire(...)
                elseif changeType == "Properties" then
                    self[key] = ...
                elseif changeType == "Function" then
                    self[key](...)
                    if createFunctionEvents then
                        inst:FindFirstChild("On"..key):Fire()
                    end
                    -- inst:FindFirstChild(key):Invoke(...)
                end
            end))
        end
    end
    -- print("FOUND REP EVENT", replicatedEvent, self)
    for key, func in pairs(functions) do
        -- logger:AtInfo():Log("Building function "..key)
        local bindableFunction = inst:FindFirstChild(key) or Instance.new("BindableFunction", inst)
        bindableFunction.Name = key
        bindableFunction.OnInvoke = function(...)
            if replicatedEvent then
                if runService:IsClient() then
                    replicatedEvent:FireServer("Function", key, ...)
                else
                    replicatedEvent:FireClient(replicationPlayer, "Function", key, ...)
                end
            end
            return func(self, ...)
        end
        bindableFunction.Parent = inst
        maid:GiveTask(bindableFunction)
    end

    for key, event in pairs(events) do
        local bindableEvent = inst:FindFirstChild(key) or Instance.new("BindableEvent", inst)
        bindableEvent.Name = key
        maid:GiveTask(bindableEvent)
        -- logger:AtInfo():Log("Building event "..key)
        if typeof(event) == "RBXScriptSignal" or event.ClassName == "Signal" then
            maid:GiveTask(event:Connect(function(...)
                if replicatedEvent then
                    if runService:IsClient() then
                        replicatedEvent:FireServer("Events", key, ...)
                    else
                        replicatedEvent:FireClient(replicationPlayer, "Events", key, ...)
                    end
                end
                bindableEvent:Fire(...)
            end))
        elseif event.ClassName == "Observable" then
            maid:GiveTask(event:Subscribe(function(...)
                if replicatedEvent then
                    if runService:IsClient() then
                        replicatedEvent:FireServer("Events", key, ...)
                    else
                        replicatedEvent:FireClient(replicationPlayer, "Events", key, ...)
                    end
                end
                bindableEvent:Fire(...)
            end))
        end
        bindableEvent.Parent = inst
    end


    --yeah I know, this is dumb, but nothing else is working and I'm tired
    local cache = {}
    for k, v in pairs(self) do
        cache[k] = v
    end
    maid:GiveTask(runService.Stepped:Connect(function()
        for k, v in pairs(self) do
            -- if self.IsSelected ~= nil then
            --     print(self[k], " - ", v)
            -- end
            if self[k] ~= cache[k] then
                cache[k] = v
                -- print("UPDATE")
                updateProperties(inst, self, maid, events, replicationPlayer)
            end
        end 
    end))

    updateProperties(inst, self, maid, events, replicationPlayer)

    maid:GiveTask(inst.Destroying:Connect(function()
        maid:Destroy()
    end))

    if runService:IsClient() then
        collectionService:AddTag(inst, "ClientInstancified")
    else
        collectionService:AddTag(inst, "ServerInstancified")
    end
end

return module