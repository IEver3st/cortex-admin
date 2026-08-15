EsAdminPermissions = EsAdminPermissions or {}

function EsAdminPermissions.build(config, actionIndex, isAceAllowed, checkQBXPermission)
    assert(type(config) == 'table', 'permission config must be a table')
    assert(type(actionIndex) == 'table', 'action index must be a table')
    assert(type(isAceAllowed) == 'function', 'ACE checker must be a function')

    checkQBXPermission = type(checkQBXPermission) == 'function' and checkQBXPermission or function()
        return nil
    end

    return function(src, actionId)
        if type(actionId) ~= 'string' or actionId == '' then return false end

        local action = actionIndex[actionId]
        local tab = action and action.tab or actionId:match('^([^.]+)%.')
        local permissions = config.Permissions or {}

        if (permissions.all and isAceAllowed(src, permissions.all))
            or isAceAllowed(src, 'vMenu.Everything') then
            return true
        end

        local aliasesExcluded = tab
            and config.VmenuAceExcludedTabs
            and config.VmenuAceExcludedTabs[tab] == true
        local vmenuPermissions = not aliasesExcluded
            and config.VmenuAcePermissions
            and config.VmenuAcePermissions[actionId]
        if type(vmenuPermissions) == 'table' then
            for index = 1, #vmenuPermissions do
                local permission = vmenuPermissions[index]
                if type(permission) == 'string' and isAceAllowed(src, permission) then return true end
            end
        end

        if config.HasQBX then
            local qbxResult = checkQBXPermission(src, actionId, tab)
            if qbxResult == true then return true end
            if qbxResult == false then return false end
        end

        local actionPermissions = config.ActionPermissions or {}
        local actionPermission = actionPermissions[actionId]
        if actionPermission and isAceAllowed(src, actionPermission) then return true end

        local tabPermission = tab and permissions[tab]
        return tabPermission ~= nil and isAceAllowed(src, tabPermission) or false
    end
end
