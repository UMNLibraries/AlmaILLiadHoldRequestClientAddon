require "Atlas.AtlasHelpers";
local rootLogger = "AtlasSystems.Addons.AlmaBarcodeLookupAddon";

luanet.load_assembly("System.Windows.Forms");
luanet.load_assembly("log4net");
luanet.load_assembly("System.Xml");

-- Load the .Net types
local types = {};
types["System.Windows.Forms.Cursor"] = luanet.import_type("System.Windows.Forms.Cursor");
types["System.Windows.Forms.Cursors"] = luanet.import_type("System.Windows.Forms.Cursors");
types["System.Windows.Forms.Application"] = luanet.import_type("System.Windows.Forms.Application");
types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");
local log = types["log4net.LogManager"].GetLogger(rootLogger);
log:Debug("Finished creating types");

-- Load settings
local settings = {};
settings.AlmaApiUrl = GetSetting("Alma API URL");
settings.AlmaApiKey = GetSetting("Alma API Key");
settings.FieldToPerformLookupWith = GetSetting("Field to Perform Lookup With");

-- Load New Settings
settings.ILLUser = GetSetting("ILL Request User ID");
settings.PickupLib = GetSetting("Pickup Library Code");

function Init()
    -- Initialize the Api with URL and Key
    AlmaApi.ApiUrl = settings.AlmaApiUrl;
    AlmaApi.ApiKey = settings.AlmaApiKey;
    log:Debug("Finished Initializing Variables");
end

-- This is the main function triggered by the button
function ImportItem() 
    -- NOTE: Function name kept as 'ImportItem' to maintain compatibility 
    -- with existing button bindings, even though we are now Routing, not just Importing.
    
    log:Debug("Starting Routing Process...");
    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].WaitCursor;

    -- 1. Get Barcode
    local barcode = nil;
    
    -- Handle {Default} setting or custom field
    if settings.FieldToPerformLookupWith == "{Default}" then
        barcode = GetFieldValue("Transaction", "ItemNumber");
    else
        local tableCol = Utility.StringSplit(".", settings.FieldToPerformLookupWith);
        if #tableCol == 2 then
            barcode = GetFieldValue(tableCol[1], tableCol[2]);
        end
    end

    if barcode == nil or barcode == "" then
        interfaceMngr:ShowMessage("No barcode found in the specified field.", "Error");
        types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
        return;
    end

    -- 2. Lookup Item to get IDs
    log:Debug("Looking up barcode: " .. barcode);
    local itemXml = AlmaApi.RetrieveItemByBarcode(barcode);
    
    if itemXml == nil then
        interfaceMngr:ShowMessage("Item lookup failed. Please check the barcode and API configuration.", "Error");
        types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
        return;
    end

    -- 3. Parse IDs
    local mmsId, holdingId, itemPid = AlmaApi.ParseItemIds(itemXml);
    
    if mmsId == nil or itemPid == nil then
        interfaceMngr:ShowMessage("Could not parse Item IDs from Alma response.", "Error");
        types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;
        return;
    end

    -- 4. Place Hold Request
    log:Debug("Placing hold for user: " .. settings.ILLUser);
    local responseXml = AlmaApi.PlaceRequest(mmsId, holdingId, itemPid, settings.ILLUser, settings.PickupLib);

    types["System.Windows.Forms.Cursor"].Current = types["System.Windows.Forms.Cursors"].Default;

    -- 5. Check Result
    if responseXml ~= nil then
        -- Try to find a Request ID to confirm success
        local reqIdNode = responseXml:SelectSingleNode("//request_id");
        if reqIdNode then
             local reqId = reqIdNode.InnerText;
             log:Info("Hold placed successfully. ID: " .. reqId);
             
             -- Write the Request ID back to ILLiad (optional, stored in ItemInfo1)
             SetFieldValue("Transaction", "ItemInfo1", "Alma Req: " .. reqId);
             
             interfaceMngr:ShowMessage("Hold successfully placed! Request ID: " .. reqId, "Success");
        else
            -- Check for error message in XML
            local errorNode = responseXml:SelectSingleNode("//errorMessage");
            local errText = "Unknown Error";
            if errorNode then errText = errorNode.InnerText end
            interfaceMngr:ShowMessage("Alma API Error: " .. errText, "API Error");
        end
    else
        interfaceMngr:ShowMessage("Failed to receive a response from the Place Request call.", "Error");
    end
end