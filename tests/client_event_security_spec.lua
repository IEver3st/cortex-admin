local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

EsAdminClientSecurity = nil
dofile(resourceRoot .. '/client/security.lua')

assert(type(EsAdminClientSecurity) == 'table', 'client security module must be available')
assert(type(EsAdminClientSecurity.isServerOrigin) == 'function', 'server-origin guard must be available')
assert(EsAdminClientSecurity.isServerOrigin(65535), 'server net id must be accepted')
assert(not EsAdminClientSecurity.isServerOrigin(nil), 'missing source must fail closed')
assert(not EsAdminClientSecurity.isServerOrigin(0), 'same-context source must be rejected')
assert(not EsAdminClientSecurity.isServerOrigin(1), 'player source must be rejected')
assert(not EsAdminClientSecurity.isServerOrigin('65535'), 'string source must be rejected')

print('privileged client event source guard tests passed')
