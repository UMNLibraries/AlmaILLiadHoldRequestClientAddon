require "Atlas.AtlasHelpers";
local rootLogger = "AtlasSystems.Addons.AlmaBarcodeLookupAddon";

luanet.load_assembly("System.Windows.Forms");
luanet.load_assembly("log4net");
luanet.load_assembly("System.Xml");

local types = {};
types["System.Windows.Forms.Cursor"] = luanet.import_type("System.Windows.Forms.Cursor");
types["System.Windows.Forms.Cursors"] = luanet.import_type("System.Windows.Forms.Cursors");
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
local log = types["log4net.LogManager"].GetLogger(rootLogger);

local settings = {};
settings.AlmaApiUrl = GetSetting("Alma API URL");
settings.AlmaApiKey = GetSetting("Alma API Key");
settings.FieldToPerformLookupWith = GetSetting("Field to Perform Lookup With");
settings.ILLUser = GetSetting("ILL Request User ID");
settings.PickupLib = GetSetting("Pickup Library Code");
settings.HoldIdField = GetSetting("Alma_Hold_ID_Field");
settings.AutoRouteQueue = GetSetting("Auto_Route_On_Success");

local interfaceMngr = nil;

function Init()
    interfaceMngr = GetInterfaceManager();
    if interfaceMngr then
        local ribbonPage = interfaceMngr:CreateRibbonPage("Hold Request");
        if ribbonPage then
            ribbonPage:CreateButton("Request Hold", GetClientImage("Search32"), "RouteItem", "Actions");
            ribbonPage:CreateButton("Check Status", GetClientImage("Refresh32"), "CheckRequestStatus", "Actions");
            ribbonPage:CreateButton("Cancel Hold", GetClientImage("Delete32"), "CancelHoldRequest", "Actions");
        end
    end

    AlmaApi.ApiUrl = settings.AlmaApiUrl;
    AlmaApi.ApiKey = settings.AlmaApiKey;
end

-- HELPER: Gets raw barcode string from the configured field
function GetRawBarcodeString()
    local barcode = nil;
    if settings.FieldToPerformLookupWith == "{Default}" then
        barcode = GetFieldValue("Transaction", "ItemNumber");
    else
        local tableCol = Utility.StringSplit(".", settings.FieldToPerformLookupWith);
        if #tableCol == 2 then barcode = GetFieldValue(tableCol[1], tableCol[2]); end
    end
    return barcode;
end

-- HELPER: Gets MMS, Holding, and Item PIDs based on a single Barcode
function GetAlmaItemIdsByBarcode(barcode)
    if barcode == nil or barcode == "" then return nil, nil, nil; end
    local itemXml = AlmaApi.RetrieveItemByBarcode(barcode);
    if itemXml == nil then return nil, nil, nil; end
    return AlmaApi.ParseItemIds(itemXml);
end

-- HELPER: Extracts all digits (IDs) from the configured field into a table
function GetRequestIdsFromField()
    local rawVal = GetFieldValue("Transaction", settings.HoldIdField);
    if rawVal == nil or rawVal == "" then return {} end
    
    local ids = {};
    for id in string.gmatch(rawVal, "%d+") do
        table.insert(ids, id);
    end
    return ids;
end

-- HELPER: Parses comma-separated barcodes into a clean table
function GetCleanBarcodesList()
    local rawBarcodes = GetRawBarcodeString();
    if not rawBarcodes or rawBarcodes == "" then return {} end

    local barcodeList = Utility.StringSplit(",", rawBarcodes);
    local cleanBarcodes = {};
    for _, b in ipairs(barcodeList) do
        local cb = Utility.Trim(b);
        if cb ~= "" then table.insert(cleanBarcodes, cb) end
    end
    return cleanBarcodes;
end

-- 1. REQUEST HOLD
function RouteItem() 
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    
    local cleanBarcodes = GetCleanBarcodesList();
    if #cleanBarcodes == 0 then
        interfaceMngr:ShowMessage("No barcodes found.", "Error");
        types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
        return;
    end

    local isMultiple = #cleanBarcodes > 1;
    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");
    
    local requestIds = {};
    local errors = {};
    
    -- Loop over all barcodes and place requests
    for _, barcode in ipairs(cleanBarcodes) do
        local mmsId, holdingId, itemPid = GetAlmaItemIdsByBarcode(barcode);
        if not mmsId then 
            table.insert(errors, barcode .. ": Could not identify item in Alma.");
        else
            local responseXml = AlmaApi.PlaceRequest(mmsId, holdingId, itemPid, settings.ILLUser, settings.PickupLib, transactionNumber, isMultiple);
            
            if responseXml ~= nil then
                local reqIdNode = responseXml:SelectSingleNode("//request_id");
                if reqIdNode then
                     table.insert(requestIds, reqIdNode.InnerText);
                else
                    local errText = "Unknown Error";
                    local errorNode = responseXml:SelectSingleNode("//errorMessage");
                    if errorNode then errText = errorNode.InnerText end
                    table.insert(errors, barcode .. ": " .. errText);
                end
            else
                table.insert(errors, barcode .. ": No response from Alma.");
            end
        end
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;

    -- Process Results
    if #requestIds > 0 then
        -- Save all IDs separated by commas
        SetFieldValue("Transaction", settings.HoldIdField, "Created " .. table.concat(requestIds, ", "));
        ExecuteCommand("Save", {});
        
        if #errors == 0 then
            log:Info("Hold IDs Saved. Checking for Auto-Route...");
            if settings.AutoRouteQueue and settings.AutoRouteQueue ~= "" then
                 local success, err = pcall(function() 
                    ExecuteCommand("Route", {settings.AutoRouteQueue, true}); 
                 end);
                 if not success then
                     log:Error("Route command FAILED: " .. tostring(err));
                     interfaceMngr:ShowMessage("Holds placed, but Auto-Route failed.", "Warning");
                 end
            else
                 interfaceMngr:ShowMessage("Holds placed successfully! IDs: " .. table.concat(requestIds, ", "), "Success");
            end
        else
            interfaceMngr:ShowMessage("Some holds placed successfully, but with errors:\n" .. table.concat(errors, "\n"), "Warning");
        end
    else
        interfaceMngr:ShowMessage("Failed to place holds:\n" .. table.concat(errors, "\n"), "Error");
    end
end

-- 2. CHECK STATUS
function CheckRequestStatus()
    local reqIds = GetRequestIdsFromField();
    if #reqIds == 0 then
        interfaceMngr:ShowMessage("No Request IDs found in " .. settings.HoldIdField .. ".", "Error");
        return;
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    local cleanBarcodes = GetCleanBarcodesList();
    local statuses = {};

    for i, reqId in ipairs(reqIds) do
        -- We map request IDs back to barcodes by their index to lookup the PIDs
        local barcode = cleanBarcodes[i];
        if barcode then
            local mmsId, holdingId, itemPid = GetAlmaItemIdsByBarcode(barcode);
            if mmsId then
                local responseXml = AlmaApi.GetRequest(mmsId, holdingId, itemPid, reqId);
                if responseXml then
                     local statusNode = responseXml:SelectSingleNode("//request_status");
                     if statusNode then
                         local status = statusNode.InnerText;
                         if status == "HISTORY" then
                            table.insert(statuses, reqId .. ": Inactive/Cancelled");
                         else
                            table.insert(statuses, reqId .. ": " .. status);
                         end
                     else
                         table.insert(statuses, reqId .. ": Request not found (Active)");
                     end
                else
                     table.insert(statuses, reqId .. ": Failed to retrieve status");
                end
            else
                 table.insert(statuses, reqId .. ": Failed to identify base item in Alma");
            end
        else
            table.insert(statuses, reqId .. ": No matching barcode found to check status");
        end
    end
    
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
    interfaceMngr:ShowMessage(table.concat(statuses, "\n"), "Status");
end

-- 3. CANCEL HOLD
function CancelHoldRequest()
    local reqIds = GetRequestIdsFromField();
    if #reqIds == 0 then
        interfaceMngr:ShowMessage("No Request IDs found in " .. settings.HoldIdField .. ".", "Error");
        return;
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    
    local cleanBarcodes = GetCleanBarcodesList();
    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");
    
    local reason = "AdditionalReason05";
    local note = transactionNumber or "";
    
    local successCount = 0;
    local failCount = 0;
    local cancelledIds = {};

    for i, reqId in ipairs(reqIds) do
        local barcode = cleanBarcodes[i];
        if barcode then
            local mmsId, holdingId, itemPid = GetAlmaItemIdsByBarcode(barcode);
            if mmsId then
                local success = AlmaApi.CancelRequest(mmsId, holdingId, itemPid, reqId, reason, note);
                if success then
                    successCount = successCount + 1;
                    table.insert(cancelledIds, reqId);
                else
                    failCount = failCount + 1;
                end
            else
                failCount = failCount + 1;
            end
        else
            failCount = failCount + 1;
        end
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;

    if successCount > 0 then
         pcall(function()
             SetFieldValue("Transaction", settings.HoldIdField, "Cancelled " .. table.concat(cancelledIds, ", "));
             ExecuteCommand("Save", {});
         end);
         
         local msg = "Cancelled " .. successCount .. " request(s).";
         if failCount > 0 then msg = msg .. "\nFailed to cancel " .. failCount .. " request(s)." end
         interfaceMngr:ShowMessage(msg, "Info");
    else
         interfaceMngr:ShowMessage("Failed to cancel holds. They may already be inactive.", "Error");
    end
end