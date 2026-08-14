--[[
    Minimal read-only LevelDB reader used by the vMenu migration fallback.

    CitizenFX stores resource KVP data in LevelDB. A resource cannot enumerate
    another resource's namespace through the KVP natives, so Cortex reads the
    active table/log files directly when vMenu is no longer installed. This
    implementation intentionally supports only the pieces required for a
    read-only snapshot: manifests, block tables, Snappy blocks and write batches.
]]

EsAdminLevelDb = EsAdminLevelDb or {}

local MAX_FILE_BYTES = 64 * 1024 * 1024
local MAX_BLOCK_BYTES = 8 * 1024 * 1024
local MAX_VALUE_BYTES = 2 * 1024 * 1024
local MAX_ENTRIES = 8192
local TABLE_MAGIC = string.char(0x57, 0xfb, 0x80, 0x8b, 0x24, 0x75, 0x47, 0xdb)

local isWindows = package and package.config and package.config:sub(1, 1) == '\\' or false

local function joinPath(base, name)
    local separator = isWindows and '\\' or '/'
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. name
    end
    return base .. separator .. name
end

local function readFile(path, maxBytes)
    local handle = io.open(path, 'rb')
    if not handle then return nil, 'open_failed' end
    local size = handle:seek('end')
    if type(size) ~= 'number' or size < 0 or size > (maxBytes or MAX_FILE_BYTES) then
        handle:close()
        return nil, 'file_too_large'
    end
    handle:seek('set', 0)
    local value = handle:read('*a')
    handle:close()
    if type(value) ~= 'string' or #value ~= size then return nil, 'read_failed' end
    return value
end

local function readVarint(data, position)
    local result = 0
    local shift = 0
    for _ = 1, 10 do
        local byte = data:byte(position)
        if not byte then return nil, position, 'truncated_varint' end
        position = position + 1
        result = result | ((byte & 0x7f) << shift)
        if byte < 0x80 then return result, position end
        shift = shift + 7
    end
    return nil, position, 'oversized_varint'
end

local function readSlice(data, position, maxLength)
    local length
    length, position = readVarint(data, position)
    if not length or length < 0 or length > (maxLength or MAX_VALUE_BYTES) then return nil, position end
    local last = position + length - 1
    if last > #data then return nil, position end
    return data:sub(position, last), last + 1
end

local function readBlockHandle(data, position)
    local offset, size
    offset, position = readVarint(data, position)
    size, position = readVarint(data, position)
    if not offset or not size or offset < 0 or size < 0 or size > MAX_BLOCK_BYTES then return nil end
    return { offset = offset, size = size }, position
end

local function snappyCopy(output, offset, length)
    if offset <= 0 or offset > #output or length < 0 then return nil end
    while length > 0 do
        local available = math.min(length, offset)
        local start = #output - offset + 1
        local chunk = output:sub(start, start + available - 1)
        if chunk == '' then return nil end
        output = output .. chunk
        length = length - #chunk
    end
    return output
end

local function decompressSnappy(data)
    local expected, position = readVarint(data, 1)
    if not expected or expected < 0 or expected > MAX_BLOCK_BYTES then return nil, 'invalid_snappy_size' end
    local output = ''

    while position <= #data and #output < expected do
        local tag = data:byte(position)
        position = position + 1
        local kind = tag & 0x03

        if kind == 0 then
            local length = tag >> 2
            if length < 60 then
                length = length + 1
            else
                local byteCount = length - 59
                if byteCount < 1 or byteCount > 4 or position + byteCount - 1 > #data then return nil, 'invalid_snappy_literal' end
                length = 0
                for index = 0, byteCount - 1 do
                    length = length | (data:byte(position + index) << (index * 8))
                end
                position = position + byteCount
                length = length + 1
            end
            if length < 0 or position + length - 1 > #data or #output + length > expected then return nil, 'truncated_snappy_literal' end
            output = output .. data:sub(position, position + length - 1)
            position = position + length
        else
            local length = 1 + (tag >> 2)
            local offset
            if kind == 1 then
                local nextByte = data:byte(position)
                if not nextByte then return nil, 'truncated_snappy_copy' end
                position = position + 1
                length = 4 + ((tag >> 2) & 0x07)
                offset = ((tag & 0xe0) << 3) | nextByte
            elseif kind == 2 then
                if position + 1 > #data then return nil, 'truncated_snappy_copy' end
                offset = data:byte(position) | (data:byte(position + 1) << 8)
                position = position + 2
            else
                if position + 3 > #data then return nil, 'truncated_snappy_copy' end
                offset = data:byte(position)
                    | (data:byte(position + 1) << 8)
                    | (data:byte(position + 2) << 16)
                    | (data:byte(position + 3) << 24)
                position = position + 4
            end
            if #output + length > expected then return nil, 'oversized_snappy_copy' end
            output = snappyCopy(output, offset, length)
            if not output then return nil, 'invalid_snappy_offset' end
        end
    end

    if #output ~= expected then return nil, 'snappy_size_mismatch' end
    return output
end

local function readTableBlock(blob, handle)
    local start = handle.offset + 1
    local finish = handle.offset + handle.size
    if start < 1 or finish > #blob or finish < start then return nil, 'invalid_block_handle' end
    local compression = blob:byte(finish + 1)
    if compression == nil then return nil, 'missing_block_trailer' end
    local block = blob:sub(start, finish)
    if compression == 0 then return block end
    if compression == 1 then return decompressSnappy(block) end
    return nil, 'unsupported_block_compression'
end

local function eachBlockEntry(block, callback)
    if type(block) ~= 'string' or #block < 4 then return false, 'invalid_block' end
    local restartCount = string.unpack('<I4', block, #block - 3)
    if restartCount < 1 or restartCount > 65536 then return false, 'invalid_restart_count' end
    local entriesEnd = #block - ((restartCount + 1) * 4)
    if entriesEnd < 0 then return false, 'invalid_restart_table' end

    local position = 1
    local previousKey = ''
    local count = 0
    while position <= entriesEnd do
        local shared, unshared, valueLength
        shared, position = readVarint(block, position)
        unshared, position = readVarint(block, position)
        valueLength, position = readVarint(block, position)
        if not shared or not unshared or not valueLength
            or shared > #previousKey or unshared > MAX_VALUE_BYTES or valueLength > MAX_VALUE_BYTES then
            return false, 'invalid_block_entry'
        end
        local keyEnd = position + unshared - 1
        local valueEnd = keyEnd + valueLength
        if keyEnd > entriesEnd or valueEnd > entriesEnd then return false, 'truncated_block_entry' end
        local key = previousKey:sub(1, shared) .. block:sub(position, keyEnd)
        local value = block:sub(keyEnd + 1, valueEnd)
        callback(key, value)
        previousKey = key
        position = valueEnd + 1
        count = count + 1
        if count > MAX_ENTRIES * 4 then return false, 'too_many_block_entries' end
    end
    return true
end

local function eachLogRecord(blob, callback)
    local blockSize = 32768
    local position = 1
    local fragments = nil

    while position + 6 <= #blob do
        local blockOffset = (position - 1) % blockSize
        local remaining = blockSize - blockOffset
        if remaining < 7 then
            position = position + remaining
        else
            local length = string.unpack('<I2', blob, position + 4)
            local recordType = blob:byte(position + 6)
            if length == 0 and (recordType == 0 or recordType == nil) then
                position = position + remaining
            elseif length > remaining - 7 or position + 6 + length > #blob then
                return false, 'truncated_log_record'
            else
                local payload = blob:sub(position + 7, position + 6 + length)
                position = position + 7 + length
                if recordType == 1 then
                    fragments = nil
                    callback(payload)
                elseif recordType == 2 then
                    fragments = { payload }
                elseif recordType == 3 and fragments then
                    fragments[#fragments + 1] = payload
                elseif recordType == 4 and fragments then
                    fragments[#fragments + 1] = payload
                    callback(table.concat(fragments))
                    fragments = nil
                else
                    fragments = nil
                end
            end
        end
    end
    return true
end

local function readManifest(kvsPath, manifestName)
    local blob, reason = readFile(joinPath(kvsPath, manifestName), 8 * 1024 * 1024)
    if not blob then return nil, reason end
    local activeFiles = {}
    local logNumber
    local previousLogNumber
    local parseError

    eachLogRecord(blob, function(record)
        if parseError then return end
        local position = 1
        while position <= #record do
            local tag
            tag, position = readVarint(record, position)
            if not tag then parseError = 'invalid_manifest_tag'; return end
            if tag == 1 then
                local value
                value, position = readSlice(record, position, 4096)
                if value == nil then parseError = 'invalid_manifest_comparator'; return end
            elseif tag == 2 or tag == 3 or tag == 4 or tag == 9 then
                local value
                value, position = readVarint(record, position)
                if not value then parseError = 'invalid_manifest_number'; return end
                if tag == 2 then logNumber = value end
                if tag == 9 then previousLogNumber = value end
            elseif tag == 5 then
                local level, key
                level, position = readVarint(record, position)
                key, position = readSlice(record, position, MAX_VALUE_BYTES)
                if level == nil or key == nil then parseError = 'invalid_compact_pointer'; return end
            elseif tag == 6 then
                local level, fileNumber
                level, position = readVarint(record, position)
                fileNumber, position = readVarint(record, position)
                if level == nil or fileNumber == nil then parseError = 'invalid_deleted_file'; return end
                activeFiles[fileNumber] = nil
            elseif tag == 7 then
                local level, fileNumber, fileSize, smallest, largest
                level, position = readVarint(record, position)
                fileNumber, position = readVarint(record, position)
                fileSize, position = readVarint(record, position)
                smallest, position = readSlice(record, position, MAX_VALUE_BYTES)
                largest, position = readSlice(record, position, MAX_VALUE_BYTES)
                if level == nil or fileNumber == nil or fileSize == nil or smallest == nil or largest == nil then
                    parseError = 'invalid_new_file'
                    return
                end
                activeFiles[fileNumber] = true
            else
                parseError = ('unsupported_manifest_tag_%s'):format(tostring(tag))
                return
            end
        end
    end)

    if parseError then return nil, parseError end
    return {
        files = activeFiles,
        logNumber = logNumber,
        previousLogNumber = previousLogNumber,
    }
end

local function applyInternalEntry(entries, prefix, internalKey, value)
    if type(internalKey) ~= 'string' or #internalKey < 8 then return end
    local userKey = internalKey:sub(1, #internalKey - 8)
    if userKey:sub(1, #prefix) ~= prefix then return end
    local packed = string.unpack('<I8', internalKey, #internalKey - 7)
    local entryType = packed & 0xff
    local sequence = packed >> 8
    local current = entries[userKey]
    if current and current.sequence > sequence then return end
    entries[userKey] = {
        sequence = sequence,
        deleted = entryType == 0,
        value = entryType == 1 and value or nil,
    }
end

local function parseTableFile(blob, prefix, entries)
    if #blob < 48 or blob:sub(-8) ~= TABLE_MAGIC then return false, 'invalid_table_footer' end
    local footerPosition = #blob - 47
    local _, position = readBlockHandle(blob, footerPosition)
    local indexHandle
    indexHandle, position = readBlockHandle(blob, position)
    if not indexHandle then return false, 'invalid_index_handle' end
    local indexBlock, reason = readTableBlock(blob, indexHandle)
    if not indexBlock then return false, reason end

    local ok, parseReason = eachBlockEntry(indexBlock, function(_, encodedHandle)
        local handle = readBlockHandle(encodedHandle, 1)
        if not handle then return end
        local dataBlock = readTableBlock(blob, handle)
        if not dataBlock then return end
        eachBlockEntry(dataBlock, function(key, value)
            applyInternalEntry(entries, prefix, key, value)
        end)
    end)
    return ok, parseReason
end

local function parseWriteBatch(record, prefix, entries)
    if type(record) ~= 'string' or #record < 12 then return end
    local sequence = string.unpack('<I8', record, 1)
    local count = string.unpack('<I4', record, 9)
    if count > MAX_ENTRIES * 4 then return end
    local position = 13
    for index = 0, count - 1 do
        local entryType = record:byte(position)
        if entryType == nil then return end
        position = position + 1
        local key
        key, position = readSlice(record, position, MAX_VALUE_BYTES)
        if not key then return end
        local value
        if entryType == 1 then
            value, position = readSlice(record, position, MAX_VALUE_BYTES)
            if value == nil then return end
        elseif entryType ~= 0 then
            return
        end
        if key:sub(1, #prefix) == prefix then
            local current = entries[key]
            local entrySequence = sequence + index
            if not current or current.sequence <= entrySequence then
                entries[key] = {
                    sequence = entrySequence,
                    deleted = entryType == 0,
                    value = value,
                }
            end
        end
    end
end

function EsAdminLevelDb.readNamespace(kvsPath, prefix)
    if type(kvsPath) ~= 'string' or kvsPath == '' or type(prefix) ~= 'string' or prefix == '' then
        return nil, { reason = 'invalid_arguments' }
    end

    local current, reason = readFile(joinPath(kvsPath, 'CURRENT'), 4096)
    local manifestName = current and current:match('^%s*(MANIFEST%-%d+)%s*$') or nil
    if not manifestName then return nil, { reason = reason or 'manifest_missing' } end
    local manifest, manifestReason = readManifest(kvsPath, manifestName)
    if not manifest then return nil, { reason = manifestReason or 'manifest_invalid' } end

    local entries = {}
    local stats = {
        reason = 'parsed',
        manifest = manifestName,
        tablesRead = 0,
        logsRead = 0,
        errors = {},
    }

    local fileNumbers = {}
    for fileNumber in pairs(manifest.files) do fileNumbers[#fileNumbers + 1] = fileNumber end
    table.sort(fileNumbers)
    for _, fileNumber in ipairs(fileNumbers) do
        local fileName = ('%06d.ldb'):format(fileNumber)
        local blob, tableReason = readFile(joinPath(kvsPath, fileName), MAX_FILE_BYTES)
        if blob then
            local ok, parseReason = parseTableFile(blob, prefix, entries)
            if ok then stats.tablesRead = stats.tablesRead + 1 else stats.errors[#stats.errors + 1] = fileName .. ':' .. tostring(parseReason) end
        else
            stats.errors[#stats.errors + 1] = fileName .. ':' .. tostring(tableReason)
        end
    end

    local logs = {}
    if manifest.previousLogNumber and manifest.previousLogNumber > 0 then logs[#logs + 1] = manifest.previousLogNumber end
    if manifest.logNumber and manifest.logNumber > 0 then logs[#logs + 1] = manifest.logNumber end
    for _, fileNumber in ipairs(logs) do
        local fileName = ('%06d.log'):format(fileNumber)
        local blob, logReason = readFile(joinPath(kvsPath, fileName), MAX_FILE_BYTES)
        if blob then
            local ok, parseReason = eachLogRecord(blob, function(record) parseWriteBatch(record, prefix, entries) end)
            if ok then stats.logsRead = stats.logsRead + 1 else stats.errors[#stats.errors + 1] = fileName .. ':' .. tostring(parseReason) end
        elseif logReason ~= 'open_failed' then
            stats.errors[#stats.errors + 1] = fileName .. ':' .. tostring(logReason)
        end
    end

    local output = {}
    local count = 0
    for key, entry in pairs(entries) do
        if not entry.deleted and type(entry.value) == 'string' and #entry.value <= MAX_VALUE_BYTES then
            count = count + 1
            if count > MAX_ENTRIES then return nil, { reason = 'too_many_entries' } end
            output[key:sub(#prefix + 1)] = entry.value
        end
    end
    stats.entryCount = count
    return output, stats
end

