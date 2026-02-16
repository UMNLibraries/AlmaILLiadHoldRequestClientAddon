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

-- Load settings
local settings = {};
settings.AlmaApiUrl = GetSetting("Alma API URL");
settings.AlmaApiKey = GetSetting("Alma API Key");
settings.FieldToPerformLookupWith = GetSetting("Field to Perform Lookup With");
settings.ILLUser = GetSetting("ILL Request User ID");
settings.PickupLib = GetSetting("Pickup Library Code");

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

-- HELPER: Gets MMS, Holding, and Item PIDs based on Barcode
function GetAlmaItemIds()
    local barcode = nil;
    if settings.FieldToPerformLookupWith == "{Default}" then
        barcode = GetFieldValue("Transaction", "ItemNumber");
    else
        local tableCol = Utility.StringSplit(".", settings.FieldToPerformLookupWith);
        if #tableCol == 2 then barcode = GetFieldValue(tableCol[1], tableCol[2]); end
    end

    if barcode == nil or barcode == "" then
        interfaceMngr:ShowMessage("No barcode found.", "Error");
        return nil, nil, nil;
    end

    local itemXml = AlmaApi.RetrieveItemByBarcode(barcode);
    if itemXml == nil then return nil, nil, nil; end

    return AlmaApi.ParseItemIds(itemXml);
end

-- HELPER: Extracts just the digits "12345" from "Created 12345" or "Cancelled 12345"
function GetRequestIdFromField()
    local rawVal = GetFieldValue("Transaction", "ItemInfo5");
    if rawVal == nil or rawVal == "" then return nil; end
    return string.match(rawVal, "%d+");
end

-- 1. REQUEST HOLD
function RouteItem() 
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    
    local mmsId, holdingId, itemPid = GetAlmaItemIds();
    if not mmsId then 
        interfaceMngr:ShowMessage("Could not identify item in Alma.", "Error");
        types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
        return; 
    end

    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");
    
    local responseXml = AlmaApi.PlaceRequest(mmsId, holdingId, itemPid, settings.ILLUser, settings.PickupLib, transactionNumber);

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;

    if responseXml ~= nil then
        local reqIdNode = responseXml:SelectSingleNode("//request_id");
        if reqIdNode then
             local reqId = reqIdNode.InnerText;
             interfaceMngr:ShowMessage("Hold placed! ID: " .. reqId, "Success");
             
             pcall(function()
                 SetFieldValue("Transaction", "ItemInfo5", "Created " .. reqId);
                 ExecuteCommand("Save", {});
             end);
        else
            local errText = "Unknown Error";
            local errorNode = responseXml:SelectSingleNode("//errorMessage");
            if errorNode then errText = errorNode.InnerText end
            interfaceMngr:ShowMessage("Alma Error: " .. errText, "API Error");
            
            pcall(function() SetFieldValue("Transaction", "ItemInfo5", "Error: " .. errText); ExecuteCommand("Save", {}); end);
        end
    else
        interfaceMngr:ShowMessage("No response from Alma.", "Error");
    end
end

-- 2. CHECK STATUS (UPDATED)
function CheckRequestStatus()
    local reqId = GetRequestIdFromField();
    if not reqId then
        interfaceMngr:ShowMessage("No Request ID found in ItemInfo5.", "Error");
        return;
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    local mmsId, holdingId, itemPid = GetAlmaItemIds();
    
    if mmsId then
        local responseXml = AlmaApi.GetRequest(mmsId, holdingId, itemPid, reqId);
        if responseXml then
             local statusNode = responseXml:SelectSingleNode("//request_status");
             if statusNode then
                 local status = statusNode.InnerText;
                 
                 -- FIX: Translate "History" to something meaningful
                 if status == "History" then
                    interfaceMngr:ShowMessage("Request is Inactive/Cancelled.", "Info");
                 else
                    interfaceMngr:ShowMessage("Current Status: " .. status, "Status");
                 end
             else
                 interfaceMngr:ShowMessage("Request not found (Active).", "Info");
             end
        else
             interfaceMngr:ShowMessage("Failed to retrieve status.", "Error");
        end
    end
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
end

-- 3. CANCEL HOLD
function CancelHoldRequest()
    local reqId = GetRequestIdFromField();
    if not reqId then
        interfaceMngr:ShowMessage("No Request ID found in ItemInfo5.", "Error");
        return;
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    local mmsId, holdingId, itemPid = GetAlmaItemIds();

    if mmsId then
        local success = AlmaApi.CancelRequest(mmsId, holdingId, itemPid, reqId);

        if success then
             interfaceMngr:ShowMessage("Request Cancelled Successfully.", "Success");
             
             pcall(function()
                 SetFieldValue("Transaction", "ItemInfo5", "Cancelled " .. reqId);
                 ExecuteCommand("Save", {});
             end);
        else
             interfaceMngr:ShowMessage("Failed to cancel. It may already be gone.", "Error");
        end
    end
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
end