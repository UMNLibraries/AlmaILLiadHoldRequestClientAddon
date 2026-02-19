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

-- Configurable Settings
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

-- HELPER: Extracts just the digits
function GetRequestIdFromField()
    local rawVal = GetFieldValue("Transaction", settings.HoldIdField);
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
    
    -- API CALL
    local responseXml = AlmaApi.PlaceRequest(mmsId, holdingId, itemPid, settings.ILLUser, settings.PickupLib, transactionNumber);

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;

    if responseXml ~= nil then
        local reqIdNode = responseXml:SelectSingleNode("//request_id");
        if reqIdNode then
             local reqId = reqIdNode.InnerText;
             
             -- SUCCESS: Update Field
             SetFieldValue("Transaction", settings.HoldIdField, "Created " .. reqId);
             
             -- SAVE 1: Commit the ID to the database immediately
             ExecuteCommand("Save", {});
             log:Info("Hold ID Saved. Checking for Auto-Route...");

             -- AUTO-ROUTE LOGIC
             if settings.AutoRouteQueue and settings.AutoRouteQueue ~= "" then
                 
                 log:Info("Attempting to route to queue: " .. settings.AutoRouteQueue);
                 
                 -- 2. Execute Route with the correct Client arguments (Queue Name, Boolean)
                 local success, err = pcall(function() 
                    ExecuteCommand("Route", {settings.AutoRouteQueue, true}); 
                 end);

                 if success then
                     log:Info("Route command executed successfully.");
                     -- The form will likely close here because we passed 'true'
                 else
                     log:Error("Route command FAILED: " .. tostring(err));
                     interfaceMngr:ShowMessage("Hold placed, but Auto-Route failed. Check logs.", "Warning");
                 end

             else
                 log:Info("Auto-Route disabled or queue name is empty.");
                 interfaceMngr:ShowMessage("Hold placed successfully! ID: " .. reqId, "Success");
             end

        else
            -- ALMA ERROR
            local errText = "Unknown Error";
            local errorNode = responseXml:SelectSingleNode("//errorMessage");
            if errorNode then errText = errorNode.InnerText end
            interfaceMngr:ShowMessage("Alma Error: " .. errText, "API Error");
            
            SetFieldValue("Transaction", settings.HoldIdField, "Error: " .. errText); 
            ExecuteCommand("Save", {}); 
        end
    else
        interfaceMngr:ShowMessage("No response from Alma.", "Error");
    end
end

-- 2. CHECK STATUS
function CheckRequestStatus()
    local reqId = GetRequestIdFromField();
    if not reqId then
        interfaceMngr:ShowMessage("No Request ID found in " .. settings.HoldIdField .. ".", "Error");
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
                 if status == "HISTORY" then
                    interfaceMngr:ShowMessage("Request is Inactive (History/Cancelled).", "Info");
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
        interfaceMngr:ShowMessage("No Request ID found in " .. settings.HoldIdField .. ".", "Error");
        return;
    end

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;
    local mmsId, holdingId, itemPid = GetAlmaItemIds();

    if mmsId then
        local success = AlmaApi.CancelRequest(mmsId, holdingId, itemPid, reqId);

        if success then
             interfaceMngr:ShowMessage("Request Cancelled Successfully.", "Success");
             
             pcall(function()
                 SetFieldValue("Transaction", settings.HoldIdField, "Cancelled " .. reqId);
                 ExecuteCommand("Save", {});
             end);
        else
             interfaceMngr:ShowMessage("Failed to cancel. It may already be gone.", "Error");
        end
    end
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
end