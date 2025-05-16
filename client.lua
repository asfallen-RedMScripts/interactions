local PickerIsOpen = false
local InteractionMarker
local StartingCoords
local CurrentInteraction
local CanStartInteraction = true
local MaxRadius = 0.0

-- RSG-Menu başlatıcı
MenuData = {}
TriggerEvent("rsg-menubase:getData", function(call)
    MenuData = call
    if Config.Debug then
          print("^2[interactions]^0 MenuData başarıyla yüklendi")
    end
  
end)

local InteractPrompt = Uiprompt:new(Config.InteractControl, "Etkileşim", nil, false)


-- Yardımcı Fonksiyonlar
function DrawMarker(type, posX, posY, posZ, dirX, dirY, dirZ, rotX, rotY, rotZ, scaleX, scaleY, scaleZ, red, green, blue, alpha, bobUpAndDown, faceCamera, p19, rotate, textureDict, textureName, drawOnEnts)
    Citizen.InvokeNative(0x2A32FAA57B937173, type, posX, posY, posZ, dirX, dirY, dirZ, rotX, rotY, rotZ, scaleX, scaleY, scaleZ, red, green, blue, alpha, bobUpAndDown, faceCamera, p19, rotate, textureDict, textureName, drawOnEnts)
end

function IsPedUsingScenarioHash(ped, scenarioHash)
    return Citizen.InvokeNative(0x34D6AC1157C8226C, ped, scenarioHash)
end

function GetNearbyObjects(coords)
    local itemset = CreateItemset(true)
    local size = Citizen.InvokeNative(0x59B57C4B06531E1E, coords, MaxRadius, itemset, 3, Citizen.ResultAsInteger())

    local objects = {}
    if size > 0 then
        for i = 0, size - 1 do
            table.insert(objects, GetIndexedItemInItemset(i, itemset))
        end
    end

    if IsItemsetValid(itemset) then
        DestroyItemset(itemset)
    end

    return objects
end

function HasCompatibleModel(entity, models)
    local entityModel = GetEntityModel(entity)
    for _, model in ipairs(models) do
        if entityModel == GetHashKey(model) then
            return model
        end
    end
    return nil
end

function CanStartInteractionAtObject(interaction, object, playerCoords, objectCoords)
    if #(playerCoords - objectCoords) > interaction.radius then
        return nil
    end
    return HasCompatibleModel(object, interaction.objects)
end

function PlayAnimation(ped, anim)
    if not DoesAnimDictExist(anim.dict) then
            if Config.Debug then
                  print("^1[interactions]^0 Geçersiz animasyon: " .. anim.dict)
            end
        return
    end

    RequestAnimDict(anim.dict)
    while not HasAnimDictLoaded(anim.dict) do
        Citizen.Wait(0)
    end

    TaskPlayAnim(ped, anim.dict, anim.name, 0.0, 0.0, -1, 1, 1.0, false, false, false, "", false)
    RemoveAnimDict(anim.dict)
end

-- Etkileşim Fonksiyonları
function StartInteractionAtCoords(interaction)
    local x, y, z = interaction.x, interaction.y, interaction.z
    local h = interaction.heading
    local ped = PlayerPedId()

    if not StartingCoords then
        StartingCoords = GetEntityCoords(ped)
    end

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)

    if interaction.scenario then
        TaskStartScenarioAtPosition(ped, GetHashKey(interaction.scenario), x, y, z, h, -1, false, true)
        
        if Config.Debug then
                 print("^2[interactions]^0 Senaryo başlatıldı: "..interaction.scenario)
        end
   
    elseif interaction.animation then
        SetEntityCoordsNoOffset(ped, x, y, z)
        SetEntityHeading(ped, h)
        PlayAnimation(ped, interaction.animation)

        if Config.Debug then
                   print("^2[interactions]^0 Animasyon başlatıldı: "..interaction.animation.dict.."/"..interaction.animation.name)
        end
 
    end

    if interaction.effect then
        if Config.Effects and Config.Effects[interaction.effect] then
            Config.Effects[interaction.effect]()
        end
    end

    CurrentInteraction = interaction
end

function StartInteractionAtObject(interaction)
    local objectHeading = GetEntityHeading(interaction.object)
    local objectCoords = GetEntityCoords(interaction.object)
    local r = math.rad(objectHeading)
    local cosr, sinr = math.cos(r), math.sin(r)
    
    local offsetX = interaction.x
    local offsetY = interaction.y
    
    interaction.x = offsetX * cosr - offsetY * sinr + objectCoords.x
    interaction.y = offsetY * cosr + offsetX * sinr + objectCoords.y
    interaction.z = interaction.z + objectCoords.z
    interaction.heading = interaction.heading + objectHeading

    StartInteractionAtCoords(interaction)
end

function StopInteraction()
    CurrentInteraction = nil
    local ped = PlayerPedId()

    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, false)
    MenuData.CloseAll()
    Citizen.Wait(100)

    if StartingCoords then
        SetEntityCoordsNoOffset(ped, StartingCoords.x, StartingCoords.y, StartingCoords.z)
        StartingCoords = nil
    end

    if Config.Debug then
          print("^2[interactions]^0 Etkileşim durduruldu")
    end
  
end

local DropPrefix = {
    PROP=true, HUMAN=true, WORLD=true, MP=true, LOBBY=true,
    GENERIC=true, SCENARIO=true, SEAT=true
}
local SeatTags  = { CHAIR=true, BENCH=true, TABLE=true }
local PlaceTags = { PORCH=true, CAMP=true, FIRE=true }

local function ucfirst(s) return (s:gsub("^%l", string.upper)) end
local function trim(s)   return (s:gsub("^%s*(.-)%s*$", "%1")) end

-- ham string içinde _LEFT / _RIGHT / _LFT / _RGT var mı?
local function extractDir(raw)
    local tag = raw:match("_(LEFT)$") or raw:match("_(RIGHT)$")
             or raw:match("_(LFT)$")  or raw:match("_(RGT)$")
    return tag and Config.Lang.SegmentMap[tag]
end

-- benzersiz ekle
local function push(t, w, seen)
    if w ~= "" and not seen[w] then t[#t+1] = w; seen[w] = true end
end

function AutoTranslateKey(key)
    if not key or key == "" then return nil end
    local L = Config.Lang

    -- tam eşleşme
    local up = key:upper()
    if L.Labels       and L.Labels[key] then return L.Labels[key] end
    if L.SegmentMap[up]                then return L.SegmentMap[up] end

    -- sadece yön yazılacaksa
    local preDir = extractDir(up);  if preDir then return preDir end

    -- obje adını sil
    key = key:gsub("^.-:%s*", ""):gsub("^%S+[ %-]", "")

    -- sınıflandır
    local seat, places, verbs, segSeen = "", {}, {}, {}
    for rawSeg in key:gmatch("[^_]+") do
        local seg = rawSeg:upper()
        if not DropPrefix[seg] and not segSeen[seg] then
            segSeen[seg] = true
            local tr = L.SegmentMap[seg] or ucfirst(rawSeg)
            if SeatTags[seg]      then seat = tr
            elseif PlaceTags[seg] then places[#places+1] = tr
            else                   verbs[#verbs+1]  = tr end
        end
    end

    -- cümleyi kur (tekrar yok)
    local out, seen = {}, {}
    push(out, table.concat(places, " "), seen)
    push(out, seat,                      seen)
    push(out, table.concat(verbs,  " "), seen)

    return #out > 0 and table.concat(out, " ") or key
end


function OpenInteractionMenu(availableInteractions)
    -- MenuData'nın yüklendiğinden emin ol
    local attempts = 0
    while not MenuData or not MenuData.Open do
        Wait(100)
        attempts = attempts + 1
        if attempts > 50 then
              if Config.Debug then
                 print("^1[interactions]^0 Hata: MenuData yüklenemedi! rsg-menubase resource'ünün çalıştığından emin olun.")
              end
            return
        end
    end

    if Config.Debug then
            print("----- DEBUG: availableInteractions -----")
for i,it in ipairs(availableInteractions) do
    print(i,
          "dir=", it.dir,
          "label=", it.label,
          "scenario=", it.scenario or (it.animation and it.animation.label))
end
print("-----------------------------------------")

    end


    local menuElements = {}
for _, it in ipairs(availableInteractions) do
    -- İngilizce ham anahtar (tooltip)
    local rawEn = nil
  
    if it.scenario  then rawEn = type(it.scenario)=="string" and it.scenario end
    if it.animation then 
        if Config.Debug then
                print(it.animation.name)
        end
      
        rawEn = it.animation.label or it.animation.name end

    -- Türkçe açıklama
    local tr = rawEn and AutoTranslateKey(rawEn) or Config.Lang.DefaultInteractionText

    -- Yön: 1) label alanı, 2) ham anahtardan (_LEFT/_RIGHT)
-- YÖN BİLGİSİ (Sol / Sağ / …)


local dir
if it.dir and it.dir ~= "" then                              
    dir = AutoTranslateKey(it.dir:upper())

elseif it.label and it.label ~= "" then                    
    dir = AutoTranslateKey(it.label:upper())

else                                                        
    dir = extractDir(rawEn and rawEn:upper() or "")
end


    -- yön zaten içerikte geçiyorsa tekrar yazma
    local visible = dir and not tr:lower():find(dir:lower(),1,true)
                   and (dir .. " " .. tr) or tr

    menuElements[#menuElements+1] = {
        label = visible,      -- menüde görünen
        desc  = rawEn or "",  -- alt açıklama (orijinal İng.)
        value = it
    }
end
    -- İptal seçeneği -----------------------------------------
    table.insert(menuElements, {
        label  = Config.Lang.CancelLabel,
        value  = "cancel",
        desc   = Config.Lang.CancelDesc,
        cancel = true
    })

    if #menuElements == 1 and menuElements[1].value == "cancel" then
        table.insert(menuElements, 1, {
            label    = Config.Lang.NoInteractionLabel,
            value    = nil,
            desc     = Config.Lang.NoInteractionDesc,
            disabled = true
        })
    end

    if Config.Debug then
        print("^2[interactions]^0 Menü açılıyor. Eleman sayısı: " .. #menuElements)
    end

    --

    MenuData.Open('default', GetCurrentResourceName(), 'interaction_menu', {
        title    = Config.Lang.InteractionMenuTitle,
        align    = Config.MenuAlign or 'top-right',
        elements = menuElements
    }, function(data, menu)
        if data.current and data.current.value then
            if data.current.value == "cancel" then
                if CurrentInteraction then StopInteraction() end
            elseif type(data.current.value) == "table" then
                local sel = data.current.value
                if sel.object then StartInteractionAtObject(sel) else StartInteractionAtCoords(sel) end
            end
            menu.close()
            PickerIsOpen = false
            SetInteractionMarker(nil)
        end
    end, function(data, menu)
        PickerIsOpen = false
        SetInteractionMarker(nil)
        if Config.Debug then
            print("^2[interactions]^0 Menü kapatıldı")
        end
       -- 
        MenuData.CloseAll()
    end)

    PickerIsOpen = true
end


function StartInteraction()
    local availableInteractions = GetAvailableInteractions()
    print("^2[interactions]^0 Bulunan etkileşim sayısı: "..tostring(#availableInteractions))

    if #availableInteractions > 0 then
        OpenInteractionMenu(availableInteractions)
    else
        PickerIsOpen = false
        SetInteractionMarker(nil)
        if CurrentInteraction then
            StopInteraction()
        end
    end
end

-- Etkileşim Kontrolleri
function IsCompatible(t, ped)
    return not t.isCompatible or t.isCompatible(ped)
end

function SortInteractions(a, b)
    if a.distance == b.distance then
        if a.object == b.object then
            local aLabel = a.scenario or (a.animation and a.animation.label) or ""
            local bLabel = b.scenario or (b.animation and b.animation.label) or ""
            return aLabel < bLabel
        else
            return a.object < b.object
        end
    else
        return a.distance < b.distance
    end
end

function AddInteractions(availableInteractions, interaction, playerPed, playerCoords, targetCoords, modelName, object)
    local distance = #(playerCoords - targetCoords)
    local displayLabel = interaction.label or modelName or "Etkileşim"

    if interaction.scenarios then
        for _, scenario in ipairs(interaction.scenarios) do
            if IsCompatible(scenario, playerPed) then
                local scenarioLabel = scenario.label or scenario.name or "Senaryo"
                table.insert(availableInteractions, {
                    x = interaction.x,
                    y = interaction.y,
                    z = interaction.z,
                    heading = interaction.heading,
                    scenario = scenario.name,
                    object = object,
                    modelName = modelName,
                    distance = distance,
                    label = displayLabel .. ": " .. scenarioLabel,
                    effect = interaction.effect,
                    dir      = interaction.label,    
                })
            end
        end
    end

    if interaction.animations then
        for _, animation in ipairs(interaction.animations) do
            if IsCompatible(animation, playerPed) then
                local animLabel = animation.label or (animation.dict .. " - " .. animation.name)
                table.insert(availableInteractions, {
                    x = interaction.x,
                    y = interaction.y,
                    z = interaction.z,
                    heading = interaction.heading,
                    animation = animation,
                    object = object,
                    modelName = modelName,
                    distance = distance,
                    label = displayLabel .. ": " .. animLabel,
                    effect = interaction.effect,
                      dir      = interaction.label,  
                })
            end
        end
    end
end

function GetAvailableInteractions()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local availableInteractions = {}

    for _, interaction in ipairs(Config.Interactions) do
        if IsCompatible(interaction, playerPed) then
            if interaction.objects then
                for _, object in ipairs(GetNearbyObjects(playerCoords)) do
                    local objectCoords = GetEntityCoords(object)
                    local modelName = CanStartInteractionAtObject(interaction, object, playerCoords, objectCoords)
                    if modelName then
                        AddInteractions(availableInteractions, interaction, playerPed, playerCoords, objectCoords, modelName, object)
                    end
                end
            else
                local targetCoords = vector3(interaction.x, interaction.y, interaction.z)
                if #(playerCoords - targetCoords) <= interaction.radius then
                    AddInteractions(availableInteractions, interaction, playerPed, playerCoords, targetCoords)
                end
            end
        end
    end

    table.sort(availableInteractions, SortInteractions)
    return availableInteractions
end

-- Eksik olan IsInteractionNearby fonksiyonu
function IsInteractionNearby(playerPed)
    local playerCoords = GetEntityCoords(playerPed)

    for _, interaction in ipairs(Config.Interactions) do
        if IsCompatible(interaction, playerPed) then
            if interaction.objects then
                for _, object in ipairs(GetNearbyObjects(playerCoords)) do
                    local objectCoords = GetEntityCoords(object)
                    if CanStartInteractionAtObject(interaction, object, playerCoords, objectCoords) then
                        return true
                    end
                end
            else
                local targetCoords = vector3(interaction.x, interaction.y, interaction.z)
                if #(playerCoords - targetCoords) <= interaction.radius then
                    return true
                end
            end
        end
    end

    return false
end

-- Marker Fonksiyonları
function SetInteractionMarker(target)
    InteractionMarker = target
end

function DrawInteractionMarker()
    if not InteractionMarker then return end

    local x, y, z
    if type(InteractionMarker) == "number" then
        x, y, z = table.unpack(GetEntityCoords(InteractionMarker))
    else
        x, y, z = table.unpack(InteractionMarker)
    end

    DrawMarker(Config.MarkerType or 1, x, y, z, 0, 0, 0, 0, 0, 0, 
               Config.MarkerSize or 0.2, Config.MarkerSize or 0.2, Config.MarkerSize or 0.2, 
               Config.MarkerColor[1] or 255, Config.MarkerColor[2] or 255, Config.MarkerColor[3] or 255, 
               Config.MarkerColor[4] or 150, false, false, 2, false, nil, nil, false)
end

function IsPedUsingInteraction(ped, interaction)
    if interaction.scenario then
        return IsPedUsingScenarioHash(ped, GetHashKey(interaction.scenario))
    elseif interaction.animation then
        return IsEntityPlayingAnim(ped, interaction.animation.dict, interaction.animation.name, 1)
    else
        return false
    end
end

-- Event Handlers
RegisterNetEvent('interactions:client:startSelectedInteraction', function(interaction)
    if interaction.object then
        StartInteractionAtObject(interaction)
    else
        StartInteractionAtCoords(interaction)
    end
    MenuData.CloseAll()
    PickerIsOpen = false
    SetInteractionMarker(nil)
end)




Citizen.CreateThread(function()
	for _, interaction in ipairs(Config.Interactions) do
		MaxRadius = math.max(MaxRadius, interaction.radius)
	end

	while true do
		local ped = PlayerPedId()

		CanStartInteraction = not IsPedDeadOrDying(ped) and not IsPedInCombat(ped)

		if CanStartInteraction and IsInteractionNearby(ped) then
			if not InteractPrompt:isEnabled() then
				InteractPrompt:setEnabledAndVisible(true)
			end
		else
			if InteractPrompt:isEnabled() then
				InteractPrompt:setEnabledAndVisible(false)
			end
		end

		Citizen.Wait(1000)
	end
end)

Citizen.CreateThread(function()
    while true do

        if IsControlJustPressed(0, Config.InteractControl) and CanStartInteraction then
            StartInteraction()
        end

    
            
       if CurrentInteraction and not IsPedUsingInteraction(PlayerPedId(), CurrentInteraction) then
            StartInteractionAtCoords(CurrentInteraction)
        end
        Citizen.Wait(0)
    end
end)