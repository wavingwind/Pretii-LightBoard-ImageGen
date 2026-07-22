--! [마개조] 실시간 스트리밍 & 선착순 반영 통합본
local function getPrelude()
    local ok, res = pcall(require, './prelude')
    if ok then return res end
    if package.preload['./prelude'] then return package.preload['./prelude']() end
    return nil
end

local prelude = getPrelude()

-- 1. 리젠 핸들러 (병렬 생성 및 즉시 치환)
package.preload["./xnai_regenHandler"] = function(...)
    return {
        regenerate = function(tid, chatIndex, descriptors)
            local gen = require('./lb-xnai.gen')
            for sceneSlot, desc in pairs(descriptors) do
                runAsync(async(function()
                    print("[마개조] 생성 시작: " .. sceneSlot)
                    local ok, data = pcall(function() return gen.generate(tid, desc) end)
                    
                    if ok and data then
                        -- 함수형 setChat으로 안전하게 해당 슬롯만 덮어쓰기
                        setChat(tid, chatIndex, function(old)
                            local pattern = 'scene="' .. sceneSlot .. '"'
                            -- 이미 데이터가 들어있지 않은 경우에만 치환
                            if not old:find(data, 1, true) then
                                local target = '<lb%-xnai ' .. pattern .. '>.-</lb%-xnai>'
                                local replacement = '<lb-xnai ' .. pattern .. '>' .. data .. '</lb-xnai>'
                                return old:gsub(target, replacement)
                            end
                            return old
                        end)
                        reloadDisplay(tid)
                    end
                end))
            end
        end
    }
end

-- 2. 메인 로직 (onResponseData)
onResponseData = async(function(tid, data)
    local lastChat = data[#data]
    if not lastChat or lastChat.role ~= 'assistant' then return data end

    local content = lastChat.content
    local descriptors = {}
    local count = 0

    -- 1. 정규식이 만든 빈 박스들에 번호표(scene_1, 2...) 붙이기
    local updatedContent = content:gsub('scene="STREAMSIGN_REPLACE_ME"', function()
        count = count + 1
        return 'scene="scene_' .. count .. '"'
    end)

    if count > 0 then
        lastChat.content = updatedContent
        
        -- 2. [핵심] 원문 텍스트에서 묘사 내용을 직접 추출
        local i = 0
        -- 대괄호가 있든 없든 Visual Content 뒤의 내용을 가져오는 루아 패턴
        for descValue in content:gmatch("Visual%s*Content.-:([^%\n]+)") do
            i = i + 1
            if i <= count then
                -- 앞뒤 지저분한 문자들(], 공백 등) 정리
                local cleanDesc = descValue:gsub("^%s*[^%a%d가-힣]*", ""):gsub("[^%a%d가-힣]*%s*$", "")
                descriptors["scene_" .. i] = { scene = cleanDesc, camera = "" }
            end
        end

        -- 3. 병렬 생성 시작
        runAsync(async(function()
            await(sleep(500))
            local regen = require('./xnai_regenHandler')
            regen.regenerate(tid, -1, descriptors)
        end))
    end
    
    return data
end)
