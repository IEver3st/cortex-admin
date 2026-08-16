EsAdminClientSecurity = EsAdminClientSecurity or {}

local SERVER_NET_ID = 65535

function EsAdminClientSecurity.isServerOrigin(eventSource)
    return eventSource == SERVER_NET_ID
end
